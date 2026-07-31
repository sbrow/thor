package main

import md "markdown"
import ts "treesitter"

import "core:fmt"
import "core:log"
import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:time"

// Fields with underscores should never be set by the user.
Page :: struct {
	section:     string,
	slug:        string,
	layout:      string,
	permalink:   string,
	url:         string,
	title:       string,
	description: string,
	date:        string,
	year:        string,
	weight:      Maybe(int),
	lastmod:     string,
	menus:       map[string]Menu_Entry,
	params: json.Value,
	content:     string,
	og:          Open_Graph,
	draft:       bool,
	_is_index:   bool `private`,
}

Pending_File :: struct {
	path:     string,
	section:  string,
	slug:     string,
	is_index: bool,
}

// site_load_content reads the content directory and populates site.pages.
// Drafts are excluded unless .Drafts is enabled.
site_load_content :: proc(site: ^Site) {
	site.pages = make(#soa[dynamic]Page, 0, 8, site_allocator(site))

	// Phase 0: Enumerate content files
	pending := make([dynamic]Pending_File, 0, 16, context.temp_allocator)
	scan_content_files(site.content_dir, "", &pending)

	// Phase 1: Pre-scan for code fence languages
	// Phase 2: Parallel grammar preload
	if .Highlight in site.markdown_extensions {
		languages := collect_languages(pending[:])
		ts.preload_grammars(languages)
	}

	// Phase 3: Load pages (grammars already cached)
	for file in pending {
		page, ok := load_page(
			file.path,
			file.section,
			file.slug,
			file.is_index,
			site.markdown_extensions,
		)
		if ok && (!page.draft || .Drafts in site.features) {
			append(&site.pages, page)
		}
	}

	for &page in site.pages {
		page.url = fmt.tprintf("%s%s", site.base_url, page.permalink)
	}

	build_menus(site)
}

// scan_content_files walks the content directory and collects Pending_File
// entries. At the root level (section=""), directories are treated as
// sections. Within a section, directories are treated as leaf bundles.
scan_content_files :: proc(dir: string, section: string, pending: ^[dynamic]Pending_File) {
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil {
		log.warnf("cannot read %s: %v", dir, err)
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		switch entry.type {
		case .Regular:
			if !is_content_file(entry.name) {
				continue
			}

			filename := strip_extension(entry.name)
			is_idx := filename == "index"
			slug := is_idx ? "" : filename

			append(
				pending,
				Pending_File {
					path = strings.clone(entry.fullpath, context.temp_allocator),
					section = section,
					slug = slug,
					is_index = is_idx,
				},
			)

		case .Directory:
			if section == "" {
				scan_content_files(entry.fullpath, entry.name, pending)
			} else {
				index_path := fmt.tprintf("%s/index.html", entry.fullpath)
				if !os.exists(index_path) {
					index_path = fmt.tprintf("%s/index.md", entry.fullpath)
				}
				if os.exists(index_path) {
					append(
						pending,
						Pending_File {
							path = strings.clone(index_path, context.temp_allocator),
							section = section,
							slug = entry.name,
							is_index = false,
						},
					)
				}
			}
		case .Undetermined, .Symlink, .Named_Pipe, .Socket, .Block_Device, .Character_Device:
		}
	}
}

// collect_languages scans .md files for code fence language identifiers
// (```lang or ~~~lang) and returns the unique set.
collect_languages :: proc(files: []Pending_File) -> []string {
	set := make(map[string]bool, context.temp_allocator)

	for file in files {
		if !strings.has_suffix(file.path, ".md") {
			continue
		}
		data, err := os.read_entire_file_from_path(file.path, context.temp_allocator)
		if err != nil {
			continue
		}
		content := string(data)

		pos := 0
		for pos < len(content) {
			newline := strings.index_byte(content[pos:], '\n')
			line_end := pos + newline if newline >= 0 else len(content)
			line := content[pos:line_end]

			i := 0
			for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
				i += 1
			}

			if i + 3 <= len(line) &&
				   (line[i] == '`' && line[i + 1] == '`' && line[i + 2] == '`') ||
			   (i + 3 <= len(line) && line[i] == '~' && line[i + 1] == '~' && line[i + 2] == '~') {
				fence_char := line[i]
				j := i + 3
				for j < len(line) && line[j] == fence_char {
					j += 1
				}
				for j < len(line) && (line[j] == ' ' || line[j] == '\t') {
					j += 1
				}
				lang_start := j
				for j < len(line) {
					c := line[j]
					if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
						break
					}
					j += 1
				}
				if j > lang_start {
					set[line[lang_start:j]] = true
				}
			}

			pos = line_end + 1
		}
	}

	result := make([dynamic]string, 0, len(set), context.temp_allocator)
	for lang in set {
		append(&result, lang)
	}
	return result[:]
}

infer_layout :: proc(section: string, is_index: bool) -> string {
	if section == "" && is_index {
		return "home"
	}
	if is_index {
		return fmt.tprintf("%s_index", section)
	}
	if section != "" {
		if len(section) > 1 && section[len(section) - 1] == 's' {
			return section[:len(section) - 1]
		}
		return section
	}
	return "page"
}

load_page :: proc(
	file_path: string,
	section: string,
	slug: string,
	is_index: bool,
	ext: bit_set[md.Extension],
) -> (
	page: Page,
	ok: bool,
) {
	data, err := os.read_entire_file_from_path(file_path, context.allocator)
	if err != nil {
		log.warnf("cannot read %s: %v", file_path, err)
		return
	}

	content := string(data)
	fm, body, parsed := parse_frontmatter(content)
	if !parsed {
		body = strings.trim_left(content, " \t\r\n")
	}

	page.section = section
	page.slug = slug
	page._is_index = is_index
	page.title = fm.title
	page.description = fm.description
	page.date = fm.date
	if page.date == "" {
		info, stat_err := os.stat(file_path, context.allocator)
		if stat_err == nil {
			page.date, _ = time.time_to_rfc3339(
				info.modification_time,
				0,
				false,
				context.allocator,
			)
			os.file_info_delete(info, context.allocator)
			log.warnf(
				"no date in frontmatter for %s, using file modification time: %s",
				file_path,
				page.date,
			)
		}
	}
	page.year = get_year(page.date)
	page.weight = fm.weight
	page.lastmod = fm.lastmod
	page.draft = fm.draft
	page.params = fm.params

	if section == "" && is_index {
		page.permalink = "/"
	} else if is_index {
		page.permalink = fmt.aprintf("/%s/", section)
	} else if section == "" {
		page.permalink = fmt.aprintf("/%s/", slug)
	} else {
		page.permalink = fmt.aprintf("/%s/%s/", section, slug)
	}

	page.menus = parse_page_menus(fm.menus, page, context.allocator)
	page.layout = fm.layout if fm.layout != "" else infer_layout(section, is_index)
	page.og = fm.og

	if strings.has_suffix(file_path, ".html") {
		page.content = strings.clone(body)
	} else {
		page.content = md.process(body, ext, file_path)
	}

	ok = true
	return
}

is_content_file :: proc(name: string) -> bool {
	return strings.has_suffix(name, ".md") || strings.has_suffix(name, ".html")
}

strip_extension :: proc(name: string) -> string {
	dot := strings.last_index(name, ".")
	if dot < 0 {
		return name
	}
	return name[:dot]
}
