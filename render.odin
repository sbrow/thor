#+feature dynamic-literals
package main

import "mustache"

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "core:time/datetime"

Page_Context :: struct {
	permalink:    string,
	title:        string,
	starred:      bool,
	has_date:     bool,
	date_iso:     string,
	date_display: string,
}

Year_Section :: struct {
	year:  string,
	posts: [dynamic]Page_Context,
}

Base_Data :: struct {
	now:            datetime.DateTime,
	author:         string,
	params:         json.Value,
	title:          string,
	og_site_name:   string,
	og_description: string,
	og_image:       string,
	og_url:         string,
	og_title:       string,
	og_type:        string,
	is_article:     bool,
}

Page_Data :: struct {
	using base:   Base_Data,
	page_title:   string,
	body_html:    string,
	has_date:     bool,
	date_iso:     string,
	date_display: string,
	is_post:      bool,
	og_section:   string,
	og_published: string,
}

Home_Data :: struct {
	using base: Base_Data,
	home_body:  string,
	list_pages: [dynamic]Page_Context,
}

Posts_Data :: struct {
	using base:    Base_Data,
	year_sections: [dynamic]Year_Section,
}

build_page_context :: proc(page: Page) -> Page_Context {
	return Page_Context {
		permalink = page.permalink,
		title = page.title,
		starred = page.is_starred,
		has_date = page.date != "",
		date_iso = page.date,
		date_display = format_date(page.date),
	}
}

strip_html_tags :: proc(s: string) -> string {
	parts: [dynamic]string
	defer delete(parts)
	in_tag := false
	start := 0
	for i in 0 ..< len(s) {
		if s[i] == '<' && !in_tag {
			if i > start {
				append(&parts, s[start:i])
			}
			in_tag = true
		} else if s[i] == '>' && in_tag {
			in_tag = false
			start = i + 1
		}
	}
	if !in_tag && start < len(s) {
		append(&parts, s[start:])
	}
	if len(parts) == 0 {
		return s
	}
	return strings.join(parts[:], "")
}

og_type :: proc(is_article: bool) -> string {
	if is_article {
		return "article"
	}
	return "website"
}

load_template :: proc(layouts_dir: string, name: string) -> string {
	data, _ := os.read_entire_file_from_path(
		fmt.tprintf("%s/%s", layouts_dir, name),
		context.allocator,
	)
	return string(data)
}

render_with_layout :: proc(
	content_tpl: string,
	data: any,
	base_tpl: string,
	partials: map[string]string,
) -> string {
	result, err := mustache.render_in_layout(content_tpl, data, base_tpl, partials)
	if err != nil {
		fmt.eprintfln("thor: mustache error: %v", err)
		return ""
	}
	return result
}

render_site :: proc(pages: []Page, config: Site) {
	sort_pages_by_date(pages)

	// Load shared resources once
	partials := load_partials(config.layouts_dir)
	base_tpl := load_template(config.layouts_dir, "base.html")
	post_tpl := load_template(config.layouts_dir, "post.html")

	now, ok := time.time_to_datetime(time.now())
	assert(ok)

	// Build base data once
	base := Base_Data {
		now            = now,
		author         = config.author,
		params         = config.params,
		og_site_name   = config.title,
		og_description = config.description,
		og_image       = fmt.tprintf("%s/avatar.jpg", config.base_url),
	}

	// Find home page
	home: Page
	has_home := false
	for page in pages {
		if page.type == .Home {
			home = page
			has_home = true
			break
		}
	}

	// Render individual content pages (skip home)
	for page in pages {
		if page.type == .Home {
			continue
		}
		html := render_page_html(page, config, post_tpl, base_tpl, partials, base)
		if .Minify in config.features {
			html = minify_html(html)
		}
		write_page(config.output_dir, page.permalink, html)
	}

	// Render home page
	if has_home {
		home_tpl := load_template(config.layouts_dir, "home.html")
		home_html := render_home_html(home, pages, config, home_tpl, base_tpl, partials, base)
		if .Minify in config.features {
			home_html = minify_html(home_html)
		}
		write_file(fmt.tprintf("%s/index.html", config.output_dir), home_html)
	}

	// Render posts list page
	posts_tpl := load_template(config.layouts_dir, "posts_list.html")
	posts_html := render_posts_html(pages, config, posts_tpl, base_tpl, partials, base)
	if .Minify in config.features {
		posts_html = minify_html(posts_html)
	}
	write_page(config.output_dir, "/posts/", posts_html)

	// Generate RSS feed
	rss := generate_rss(pages, config)
	write_file(fmt.tprintf("%s/index.xml", config.output_dir), rss)

	// Generate sitemap
	sitemap := generate_sitemap(pages, config.base_url)
	write_file(fmt.tprintf("%s/sitemap.xml", config.output_dir), sitemap)

	// Copy and optionally minify assets directory
	copy_assets_dir(config.assets_dir, config.output_dir, config.features)

	// Generate robots.txt
	robots := fmt.aprintf("User-agent: *\nAllow: /\nSitemap: %s/sitemap.xml\n", config.base_url)
	write_file(fmt.tprintf("%s/robots.txt", config.output_dir), robots)

	total := len(pages) + 1
	if !has_home {
		total += 1
	}
	fmt.printfln("Rendered %d pages to %s", total, config.output_dir)
}

render_page_html :: proc(
	page: Page,
	config: Site,
	content_tpl: string,
	base_tpl: string,
	partials: map[string]string,
	base: Base_Data,
) -> string {
	is_article := page.type == .Post
	data := Page_Data {
		base = base,
	}
	data.title = fmt.tprintf("%s | %s", page.title, config.title)
	data.page_title = page.title
	data.body_html = page.body_html
	data.has_date = page.date != ""
	data.date_iso = page.date
	data.date_display = format_date(page.date)
	data.is_post = is_article
	data.og_url = fmt.tprintf("%s%s", config.base_url, page.permalink)
	data.og_title = strip_html_tags(page.title)
	data.og_type = og_type(is_article)
	data.is_article = is_article
	data.og_section = "posts"
	data.og_published = page.date
	return render_with_layout(content_tpl, data, base_tpl, partials)
}

render_home_html :: proc(
	home: Page,
	pages: []Page,
	config: Site,
	content_tpl: string,
	base_tpl: string,
	partials: map[string]string,
	base: Base_Data,
) -> string {
	list_pages := make([dynamic]Page_Context)
	defer delete(list_pages)
	for page in pages {
		if page.type == .Home {
			continue
		}
		append(&list_pages, build_page_context(page))
	}

	data := Home_Data {
		base = base,
	}
	data.title = config.title
	data.home_body = home.body_html
	data.list_pages = list_pages
	data.og_url = fmt.tprintf("%s/", config.base_url)
	data.og_title = config.title
	data.og_type = "website"
	data.is_article = false
	return render_with_layout(content_tpl, data, base_tpl, partials)
}

render_posts_html :: proc(
	pages: []Page,
	config: Site,
	content_tpl: string,
	base_tpl: string,
	partials: map[string]string,
	base: Base_Data,
) -> string {
	year_sections := make([dynamic]Year_Section)
	defer delete(year_sections)
	current_year := ""
	for page in pages {
		if page.type != .Post {
			continue
		}
		year := get_year(page.date)
		if year != current_year {
			append(&year_sections, Year_Section{year = year})
			current_year = year
		}
		append(&year_sections[len(year_sections) - 1].posts, build_page_context(page))
	}

	data := Posts_Data {
		base = base,
	}
	data.title = fmt.tprintf("Posts | %s", config.title)
	data.year_sections = year_sections
	data.og_url = fmt.tprintf("%s/posts/", config.base_url)
	data.og_title = "Posts"
	data.og_type = "website"
	data.is_article = false
	return render_with_layout(content_tpl, data, base_tpl, partials)
}

load_partials :: proc(layouts_dir: string) -> map[string]string {
	partials: map[string]string
	partials_dir := fmt.tprintf("%s/partials", layouts_dir)
	load_partials_recursive(&partials, partials_dir, "")
	return partials
}

load_partials_recursive :: proc(
	partials: ^map[string]string,
	base_dir: string,
	rel_prefix: string,
) {
	entries, err := os.read_all_directory_by_path(base_dir, context.allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		#partial switch entry.type {
		case .Regular:
			name := entry.name
			if !strings.has_suffix(name, ".html") {
				continue
			}
			stripped := name[:len(name) - len(".html")]
			key := stripped
			if rel_prefix != "" {
				key = fmt.tprintf("%s/%s", rel_prefix, stripped)
			}
			data, ok := os.read_entire_file_from_path(entry.fullpath, context.allocator)
			if ok == nil {
				partials[key] = string(data)
			}
		case .Directory:
			sub_prefix := entry.name
			if rel_prefix != "" {
				sub_prefix = fmt.tprintf("%s/%s", rel_prefix, entry.name)
			}
			load_partials_recursive(partials, entry.fullpath, sub_prefix)
		}
	}
}

format_date :: proc(iso: string) -> string {
	if len(iso) < 10 {
		return ""
	}
	date, _, _, _ := time.iso8601_to_components(iso)
	return fmt.aprintf("%s %d, %d", time.Month(date.month), date.day, date.year)
}

get_year :: proc(iso: string) -> string {
	if len(iso) < 4 {
		return ""
	}
	return iso[:4]
}

sort_pages_by_date :: proc(pages: []Page) {
	for i in 1 ..< len(pages) {
		key := pages[i]
		j := i - 1
		for j >= 0 && pages[j].date < key.date {
			pages[j + 1] = pages[j]
			j -= 1
		}
		pages[j + 1] = key
	}
}

write_page :: proc(output_dir: string, permalink: string, html: string) {
	rel := permalink
	if len(rel) > 0 && rel[0] == '/' {
		rel = rel[1:]
	}

	dir := fmt.tprintf("%s/%s", output_dir, rel)
	if err := os.make_directory_all(dir); err != nil && err != .Exist {
		fmt.eprintfln("thor: cannot create %s: %v", dir, err)
		return
	}

	file_path := fmt.tprintf("%s/index.html", dir)
	write_file(file_path, html)
}

write_file :: proc(path: string, html: string) {
	if err := os.write_entire_file_from_string(path, html); err != nil {
		fmt.eprintfln("thor: cannot write %s: %v", path, err)
	}
}

