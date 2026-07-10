package main

import cm "vendor:commonmark"

import "core:fmt"
import "core:os"
import "core:strings"

Page_Type :: enum {
	Home,
	Post,
	Standalone,
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
walk_content :: proc(content_path: string, include_drafts: bool) -> []Page {
	pages: [dynamic]Page

	collect_home(&pages, content_path)
	collect_standalone(&pages, content_path)

	posts_path := fmt.tprintf("%s/posts", content_path)
	if os.exists(posts_path) {
		collect_posts(&pages, posts_path)
	}

	if !include_drafts {
		filtered: [dynamic]Page
		for &page in pages {
			if !page.draft {
				append(&filtered, page)
			}
		}
		delete(pages)
		return filtered[:]
	}

	return pages[:]
}

collect_home :: proc(pages: ^[dynamic]Page, content_path: string) {
	html_path := fmt.tprintf("%s/index.html", content_path)
	if os.exists(html_path) {
		page, ok := load_page(html_path, .Home, "")
		if ok {
			page.permalink = "/"
			append(pages, page)
		}
		return
	}

	md_path := fmt.tprintf("%s/index.md", content_path)
	if os.exists(md_path) {
		page, ok := load_page(md_path, .Home, "")
		if ok {
			page.permalink = "/"
			append(pages, page)
		}
	}
}

collect_standalone :: proc(pages: ^[dynamic]Page, content_path: string) {
	entries, err := os.read_all_directory_by_path(content_path, context.allocator)
	if err != nil {
		fmt.eprintfln("thor: cannot read %s: %v", content_path, err)
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
		page, ok := load_page(entry.fullpath, .Standalone, slug)
		if ok {
			append(pages, page)
		}
	}
}

collect_posts :: proc(pages: ^[dynamic]Page, posts_path: string) {
	entries, err := os.read_all_directory_by_path(posts_path, context.allocator)
	if err != nil {
		fmt.eprintfln("thor: cannot read %s: %v", posts_path, err)
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
			page, ok := load_page(entry.fullpath, .Post, slug)
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
			page, ok := load_page(index_path, .Post, entry.name)
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
) -> (
	page: Page,
	ok: bool,
) {
	data, err := os.read_entire_file_from_path(file_path, context.allocator)
	if err != nil {
		fmt.eprintfln("thor: cannot read %s: %v", file_path, err)
		return
	}

	content := string(data)
	fm, body, parsed := parse_frontmatter(content)
	if !parsed {
		fmt.eprintfln("thor: no frontmatter in %s", file_path)
		return
	}

	page.type        = page_type
	page.slug        = slug
	page.title       = fm.title
	page.description = fm.description
	page.date        = fm.date
	page.draft       = fm.draft
	page.is_starred  = fm.isStarred
	page.menu        = fm.menu
	page.body        = strings.clone(body)

	if strings.has_suffix(file_path, ".html") {
		page.body_html = strings.clone(body)
	} else {
		clean_body, defs := strip_definitions(body)
		html := cm.markdown_to_html_from_string(clean_body, {.Unsafe})
		page.body_html = inject_sidenotes(html, defs)
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
			fmt.eprintfln("thor: cannot copy %s: %v", entry.name, err)
		}
	}
}
