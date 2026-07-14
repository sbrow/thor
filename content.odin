package main

import cm "vendor:commonmark"

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

Page_Type :: enum {
	Standalone,
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
	body:        string,
	body_html:   string,
	bundle_dir:  string,
}

// walk_content reads the content directory and returns all non-draft pages
// (or all pages if include_drafts is true).
//
// TODO: What is the lifetime of pages?
walk_content :: proc(site: ^Site) -> []Page {
	content_path := site.content_dir
	include_drafts := site.drafts
	sectionate := site.sectionate

	allocator := site_allocator(site)

	pages := make([dynamic]Page, allocator)

	collect_home(&pages, content_path, sectionate)
	collect_standalone(&pages, content_path, sectionate)

	posts_path := fmt.tprintf("%s/posts", content_path)
	if os.exists(posts_path) {
		collect_posts(&pages, posts_path, sectionate)
	}

	if include_drafts {
		return pages[:]
	} else {
		filtered := make([dynamic]Page, allocator)
		for &page in pages {
			if !page.draft {
				append(&filtered, page)
			}
		}
		delete(pages)
		return filtered[:]
	}
}

collect_home :: proc(pages: ^[dynamic]Page, content_path: string, sectionate: bool) {
	html_path := fmt.tprintf("%s/index.html", content_path)
	if os.exists(html_path) {
		page, ok := load_page(html_path, .Home, "", sectionate)
		if ok {
			page.permalink = "/"
			append(pages, page)
		}
		return
	}

	md_path := fmt.tprintf("%s/index.md", content_path)
	if os.exists(md_path) {
		page, ok := load_page(md_path, .Home, "", sectionate)
		if ok {
			page.permalink = "/"
			append(pages, page)
		}
	}
}

collect_standalone :: proc(pages: ^[dynamic]Page, content_path: string, sectionate: bool) {
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
		page, ok := load_page(entry.fullpath, .Standalone, slug, sectionate)
		if ok {
			append(pages, page)
		}
	}
}

collect_posts :: proc(pages: ^[dynamic]Page, posts_path: string, sectionate: bool) {
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
			page, ok := load_page(entry.fullpath, .Post, slug, sectionate)
			if ok {
				append(pages, page)
			}
		case .Directory:
			index_path := fmt.tprintf("%s/index.html", entry.fullpath)
			if !os.exists(index_path) {
				index_path = fmt.tprintf("%s/index.md", entry.fullpath)
			}
			if !os.exists(index_path) {
				continue
			}
			page, ok := load_page(index_path, .Post, entry.name, sectionate)
			if ok {
				page.bundle_dir = entry.fullpath
				append(pages, page)
			}
		case .Undetermined, .Symlink, .Named_Pipe, .Socket, .Block_Device, .Character_Device:
		}
	}
}

load_page :: proc(
	file_path: string,
	page_type: Page_Type,
	slug: string,
	sectionate: bool,
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
	page.body = strings.clone(body)

	if strings.has_suffix(file_path, ".html") {
		page.body_html = strings.clone(body)
	} else {
		expanded := expand_emoji(body)
		clean_body, sn_defs, mn_defs := strip_definitions(expanded)
		html := cm.markdown_to_html_from_string(clean_body, {.Unsafe})
		html = highlight_code(inject_alerts(inject_notes(html, sn_defs, mn_defs)), file_path)
		if sectionate {
			html = wrap_sections(html)
		}
		page.body_html = html
	}

	switch page_type {
	case .Home:
		page.permalink = "/"
	case .Post:
		page.permalink = fmt.aprintf("/posts/%s/", slug)
	case .Standalone:
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

// copy_static_assets copies non-content files from the content root to the output directory.
copy_static_assets :: proc(content_path: string, output_dir: string) {
	entries, err := os.read_all_directory_by_path(content_path, context.allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		if entry.type != .Regular {
			continue
		}
		if is_content_file(entry.name) {
			continue
		}

		dest := fmt.tprintf("%s/%s", output_dir, entry.name)
		if err := os.copy_file(dest, entry.fullpath); err != nil {
			log.warnf("thor: cannot copy %s: %v", entry.name, err)
		}
	}
}

