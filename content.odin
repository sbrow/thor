package main

import cm "vendor:commonmark"

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

Page_Type :: enum {
	Page,
	Post,
	Home,
}

Page :: struct {
	type:        Page_Type,
	slug:        string,
	permalink:   string,
	title:       string,
	description: string,
	date:        string,
	draft:       bool,
	is_starred:  bool,
	menu:        string,
	body_html:   string,
	bundle_dir:  string,
}

// site_load_content reads the content directory and populates site.pages.
// Drafts are excluded unless .Drafts is enabled.
site_load_content :: proc(site: ^Site) {
	site.pages = make([dynamic]Page, 0, 8, site_allocator(site))

	load_homepage(site)
	load_pages(site)
	load_posts(site)
}

load_homepage :: proc(site: ^Site) {
	content_path := site.content_dir
	ext := site.markdown_extensions

	html_path := fmt.tprintf("%s/index.html", content_path)
	if os.exists(html_path) {
		page, ok := load_page(html_path, .Home, "", ext)
		if ok && (!page.draft || .Drafts in site.features) {
			page.permalink = "/"
			append(&site.pages, page)
		}
		return
	}

	md_path := fmt.tprintf("%s/index.md", content_path)
	if os.exists(md_path) {
		page, ok := load_page(md_path, .Home, "", ext)
		if ok && (!page.draft || .Drafts in site.features) {
			page.permalink = "/"
			append(&site.pages, page)
		}
	}
}

load_pages :: proc(site: ^Site) {
	content_path := site.content_dir
	ext := site.markdown_extensions

	entries, err := os.read_all_directory_by_path(content_path, context.allocator)
	if err != nil {
		log.warnf("thor: cannot read %s: %v", content_path, err)
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		if !is_content_file(entry.name) {
			continue
		}
		if entry.name == "index.md" || entry.name == "index.html" {
			continue
		}
		if entry.type != .Regular {
			continue
		}

		slug := strip_extension(entry.name)
		page, ok := load_page(entry.fullpath, .Page, slug, ext)
		if ok && (!page.draft || .Drafts in site.features) {
			append(&site.pages, page)
		}
	}
}

load_posts :: proc(site: ^Site) {
	posts_path := fmt.tprintf("%s/posts", site.content_dir)
	if !os.exists(posts_path) {
		return
	}

	ext := site.markdown_extensions
	entries, err := os.read_all_directory_by_path(posts_path, context.allocator)
	if err != nil {
		log.warnf("thor: cannot read %s: %v", posts_path, err)
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		switch entry.type {
		case .Regular:
			if !is_content_file(entry.name) {
				continue
			}
			slug := strip_extension(entry.name)
			page, ok := load_page(entry.fullpath, .Post, slug, ext)
			if ok && (!page.draft || .Drafts in site.features) {
				append(&site.pages, page)
			}
		case .Directory:
			index_path := fmt.tprintf("%s/index.html", entry.fullpath)
			if !os.exists(index_path) {
				index_path = fmt.tprintf("%s/index.md", entry.fullpath)
			}
			if !os.exists(index_path) {
				continue
			}
			page, ok := load_page(index_path, .Post, entry.name, ext)
			if ok && (!page.draft || .Drafts in site.features) {
				page.bundle_dir = entry.fullpath
				append(&site.pages, page)
			}
		case .Undetermined, .Symlink, .Named_Pipe, .Socket, .Block_Device, .Character_Device:
		}
	}
}

load_page :: proc(
	file_path: string,
	page_type: Page_Type,
	slug: string,
	ext: bit_set[Markdown_Extension],
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

	page.type = page_type
	page.slug = slug
	page.title = fm.title
	page.description = fm.description
	page.date = fm.date
	page.draft = fm.draft
	page.is_starred = fm.isStarred
	page.menu = fm.menu

	if strings.has_suffix(file_path, ".html") {
		page.body_html = strings.clone(body)
	} else {
		sn_defs := make(map[string]string)
		mn_defs := make(map[string]string)
		clean_body := body
		if .Sidenotes in ext {
			clean_body, sn_defs, mn_defs = strip_definitions(body)
		}
		html := cm.markdown_to_html_from_string(clean_body, {.Unsafe})
		if .Emoji in ext {
			html = expand_emoji(html)
		}
		if .Sidenotes in ext {
			html = inject_notes(html, sn_defs, mn_defs)
		}
		if .Alerts in ext {
			html = inject_alerts(html)
		}
		if .Highlight in ext {
			html = highlight_code(html, file_path)
		}
		if .Sections in ext {
			html = wrap_sections(html)
		}
		page.body_html = html
	}

	switch page_type {
	case .Home:
		page.permalink = "/"
	case .Post:
		page.permalink = fmt.aprintf("/posts/%s/", slug)
	case .Page:
		page.permalink = fmt.aprintf("/%s/", slug)
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

// copy_assets_dir recursively copies files from assets_dir to output_dir.
// .css files are minified when .Minify is enabled; all other files are copied verbatim.
// Silently skips if assets_dir doesn't exist.
copy_assets_dir :: proc(assets_dir: string, output_dir: string, features: bit_set[Feature]) {
	if !os.exists(assets_dir) {
		return
	}
	copy_assets_recursive(assets_dir, "", output_dir, features)
}

copy_assets_recursive :: proc(
	current: string,
	rel_prefix: string,
	output_dir: string,
	features: bit_set[Feature],
) {
	entries, err := os.read_all_directory_by_path(current, context.allocator)
	if err != nil {
		log.warnf("thor: cannot read %s: %v", current, err)
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		rel := rel_prefix == "" ? entry.name : fmt.tprintf("%s/%s", rel_prefix, entry.name)
		switch entry.type {
		case .Regular:
			dest := fmt.tprintf("%s/%s", output_dir, rel)
			if idx := strings.last_index(dest, "/"); idx >= 0 {
				if err := os.make_directory_all(dest[:idx]); err != nil && err != .Exist {
					log.warnf("thor: cannot create %s: %v", dest[:idx], err)
					continue
				}
			}
			if .Minify in features && strings.has_suffix(entry.name, ".css") {
				data, read_err := os.read_entire_file_from_path(entry.fullpath, context.allocator)
				if read_err != nil {
					log.warnf("thor: cannot read %s: %v", entry.fullpath, read_err)
					continue
				}
				minified := minify_css(string(data))
				write_file(dest, minified)
			} else {
				if err := os.copy_file(dest, entry.fullpath); err != nil {
					log.warnf("thor: cannot copy %s: %v", entry.fullpath, err)
				}
			}
		case .Directory:
			copy_assets_recursive(entry.fullpath, rel, output_dir, features)
		case .Undetermined, .Symlink, .Named_Pipe, .Socket, .Block_Device, .Character_Device:
		}
	}
}

