package main

import md "markdown"

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

// Fields with underscores should never be set by the user.
Page :: struct {
	section:     string,
	slug:        string,
	layout:      string,
	permalink:   string,
	title:       string,
	description: string,
	date:        string,
	menu:        string,
	body_html:   string,
	draft:       bool,
	is_starred:  bool,
	_is_index:   bool `private`,
}

// site_load_content reads the content directory and populates site.pages.
// Drafts are excluded unless .Drafts is enabled.
site_load_content :: proc(site: ^Site) {
	site.pages = make([dynamic]Page, 0, 8, site_allocator(site))
	scan_content(site, site.content_dir, "")
}

// scan_content walks the content directory. At the root level (section=""),
// directories are treated as sections. Within a section, directories are
// treated as leaf bundles (directory with an index file).
scan_content :: proc(site: ^Site, dir: string, section: string) {
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil {
		log.warnf("thor: cannot read %s: %v", dir, err)
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

			page, ok := load_page(entry.fullpath, section, slug, is_idx, site.markdown_extensions)
			if ok && (!page.draft || .Drafts in site.features) {
				append(&site.pages, page)
			}

		case .Directory:
			if section == "" {
				scan_content(site, entry.fullpath, entry.name)
			} else {
				index_path := fmt.tprintf("%s/index.html", entry.fullpath)
				if !os.exists(index_path) {
					index_path = fmt.tprintf("%s/index.md", entry.fullpath)
				}
				if os.exists(index_path) {
					page, ok := load_page(
						index_path,
						section,
						entry.name,
						false,
						site.markdown_extensions,
					)
					if ok && (!page.draft || .Drafts in site.features) {
						append(&site.pages, page)
					}
				}
			}
		case .Undetermined, .Symlink, .Named_Pipe, .Socket, .Block_Device, .Character_Device:
		}
	}
}

infer_layout :: proc(section: string, is_index: bool) -> string {
	if section == "" && is_index {
		return "home"
	}
	if is_index {
		return fmt.tprintf("%s_index", section)
	}
	if section != "" {
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
		log.warnf("thor: cannot read %s: %v", file_path, err)
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
	page.draft = fm.draft
	page.is_starred = fm.isStarred
	page.menu = fm.menu
	page.layout = fm.layout if fm.layout != "" else infer_layout(section, is_index)

	if strings.has_suffix(file_path, ".html") {
		page.body_html = strings.clone(body)
	} else {
		page.body_html = md.process(body, ext, file_path)
	}

	if section == "" && is_index {
		page.permalink = "/"
	} else if is_index {
		page.permalink = fmt.aprintf("/%s/", section)
	} else if section == "" {
		page.permalink = fmt.aprintf("/%s/", slug)
	} else {
		page.permalink = fmt.aprintf("/%s/%s/", section, slug)
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

