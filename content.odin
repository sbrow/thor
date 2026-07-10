package main

import "core:fmt"
import "core:os"
import "core:strings"

Page_Type :: enum {
	Post,
	Standalone,
}

Page :: struct {
	type:       Page_Type,
	slug:       string,
	permalink:  string,
	title:      string,
	date:       string,
	draft:      bool,
	is_starred: bool,
	menu:       string,
	body:       string,
	bundle_dir: string,
}

// walk_content reads the content directory and returns all non-draft pages
// (or all pages if include_drafts is true).
walk_content :: proc(content_path: string, include_drafts: bool) -> []Page {
	pages: [dynamic]Page

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

collect_standalone :: proc(pages: ^[dynamic]Page, content_path: string) {
	entries, err := os.read_all_directory_by_path(content_path, context.allocator)
	if err != nil {
		fmt.eprintfln("thor: cannot read %s: %v", content_path, err)
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		if !strings.has_suffix(entry.name, ".md") {
			continue
		}
		if entry.type != .Regular {
			continue
		}

		slug := entry.name[:len(entry.name) - 3]
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
			if !strings.has_suffix(entry.name, ".md") {
				continue
			}
			slug := entry.name[:len(entry.name) - 3]
			page, ok := load_page(entry.fullpath, .Post, slug)
			if ok {
				append(pages, page)
			}
		case .Directory:
			index_path := fmt.tprintf("%s/index.md", entry.fullpath)
			if !os.exists(index_path) {
				continue
			}
			page, ok := load_page(index_path, .Post, entry.name)
			if ok {
				page.bundle_dir = entry.fullpath
				append(pages, page)
			}
		case .Undetermined, .Symlink, .Named_Pipe, .Socket, .Block_Device, .Character_Device:
		// Do nothing
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

	page.type = page_type
	page.slug = slug
	page.title = fm.title
	page.date = fm.date
	page.draft = fm.draft
	page.is_starred = fm.isStarred
	page.menu = fm.menu
	page.body = strings.clone(body)

	switch page_type {
	case .Post:
		page.permalink = fmt.aprintf("/posts/%s/", slug)
	case .Standalone:
		page.permalink = fmt.aprintf("/%s/", slug)
	}

	ok = true
	return
}

