#+feature dynamic-literals
package main

import mustache "mustache"

import "core:fmt"
import "core:os"
import "core:strings"

MONTHS: [12]string = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

Page_Context :: struct {
	permalink:    string,
	title:        string,
	star:         string,
	has_date:     bool,
	date_iso:     string,
	date_display: string,
}

Year_Section :: struct {
	year:  string,
	posts: [dynamic]Page_Context,
}

Year_Slice :: struct {
	year:  string,
	posts: []Page_Context,
}

build_page_context :: proc(page: Page) -> Page_Context {
	star := ""
	if page.is_starred {
		star = ICON_STAR
	}
	return Page_Context{
		permalink = page.permalink,
		title = page.title,
		star = star,
		has_date = page.date != "",
		date_iso = page.date,
		date_display = format_date(page.date),
	}
}

build_social_context :: proc(config: Site_Config) -> [dynamic]map[string]string {
	social_ctx := make([dynamic]map[string]string)
	for link in config.social {
		append(
			&social_ctx,
			map[string]string{
				"name" = link.name,
				"url"  = link.url,
				"icon" = social_icon(link.name),
			},
		)
	}
	return social_ctx
}

strip_html_tags :: proc(s: string) -> string {
	parts: [dynamic]string
	defer delete(parts)
	in_tag := false
	start := 0
	for i in 0..<len(s) {
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

render_site :: proc(pages: []Page, config: Site_Config) {
	sort_pages_by_date(pages)

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
		html := render_page_html(page, config)
		write_page(config.output_dir, page.permalink, html)
	}

	// Render home page
	if has_home {
		home_html := render_home_html(home, pages, config)
		write_file(fmt.tprintf("%s/index.html", config.output_dir), home_html)
	}

	// Render posts list page
	posts_html := render_posts_html(pages, config)
	write_page(config.output_dir, "/posts/", posts_html)

	// Generate RSS feed
	rss := generate_rss(pages, config)
	write_file(fmt.tprintf("%s/index.xml", config.output_dir), rss)

	// Generate sitemap
	sitemap := generate_sitemap(pages, config.base_url)
	write_file(fmt.tprintf("%s/sitemap.xml", config.output_dir), sitemap)

	// Copy static assets (avatar, favicon, etc.)
	copy_static_assets(config.content_dir, config.output_dir)

	// Generate robots.txt
	robots := fmt.aprintf("User-agent: *\nAllow: /\nSitemap: %s/sitemap.xml\n", config.base_url)
	write_file(fmt.tprintf("%s/robots.txt", config.output_dir), robots)

	total := len(pages) + 1
	if !has_home {
		total += 1
	}
	fmt.printfln("Rendered %d pages to %s", total, config.output_dir)
}

render_page_html :: proc(page: Page, config: Site_Config) -> string {
	social_ctx := build_social_context(config)
	defer delete(social_ctx)

	is_article := page.type == .Post

	data := map[string]any{
		"title"         = fmt.tprintf("%s | %s", page.title, config.title),
		"page_title"    = page.title,
		"body_html"     = page.body_html,
		"has_date"      = page.date != "",
		"date_iso"      = page.date,
		"date_display"  = format_date(page.date),
		"is_post"       = is_article,
		"home_icon"     = ICON_HOME,
		"chevron_up"    = ICON_CHEVRON_UP,
		"year"          = "2026",
		"author"        = config.author,
		"social"        = social_ctx[:],
		"og_url"        = fmt.tprintf("%s%s", config.base_url, page.permalink),
		"og_site_name"  = config.title,
		"og_title"      = strip_html_tags(page.title),
		"og_description" = config.description,
		"og_type"       = og_type(is_article),
		"is_article"    = is_article,
		"og_section"    = "posts",
		"og_published"  = page.date,
		"og_image"      = fmt.tprintf("%s/avatar.jpg", config.base_url),
	}

	partials := load_partials(config.layouts_dir)

	post_tpl, _ := os.read_entire_file_from_path(	fmt.tprintf("%s/post.html", config.layouts_dir), context.allocator)
	base_tpl, _ := os.read_entire_file_from_path(	fmt.tprintf("%s/base.html", config.layouts_dir), context.allocator)

	result, err := mustache.render_in_layout(
		string(post_tpl),
		data,
		string(base_tpl),
		partials,
	)
	if err != nil {
		fmt.eprintfln("thor: mustache error rendering page: %v", err)
		return ""
	}
	return result
}

load_partials :: proc(layouts_dir: string) -> map[string]string {
	partials: map[string]string

	nav, _ := os.read_entire_file_from_path(fmt.tprintf("%s/partials/nav.html", layouts_dir), context.allocator)
	partials["nav"] = string(nav)

	footer, _ := os.read_entire_file_from_path(fmt.tprintf("%s/partials/footer.html", layouts_dir), context.allocator)
	partials["footer"] = string(footer)

	head, _ := os.read_entire_file_from_path(fmt.tprintf("%s/partials/head.html", layouts_dir), context.allocator)
	partials["head"] = string(head)

	return partials
}

render_home_html :: proc(home: Page, pages: []Page, config: Site_Config) -> string {
	list_pages := make([dynamic]Page_Context)
	defer delete(list_pages)
	for page in pages {
		if page.type == .Home {
			continue
		}
		append(&list_pages, build_page_context(page))
	}

	social_ctx := build_social_context(config)
	defer delete(social_ctx)

	data := map[string]any{
		"title"          = config.title,
		"home_body"      = home.body_html,
		"list_pages"     = list_pages[:],
		"home_icon"      = ICON_HOME,
		"chevron_up"     = ICON_CHEVRON_UP,
		"year"           = "2026",
		"author"         = config.author,
		"social"         = social_ctx[:],
		"og_url"         = fmt.tprintf("%s/", config.base_url),
		"og_site_name"   = config.title,
		"og_title"       = config.title,
		"og_description" = config.description,
		"og_type"        = "website",
		"is_article"     = false,
		"og_image"       = fmt.tprintf("%s/avatar.jpg", config.base_url),
	}

	partials := load_partials(config.layouts_dir)

	home_tpl, _ := os.read_entire_file_from_path(	fmt.tprintf("%s/home.html", config.layouts_dir), context.allocator)
	base_tpl, _ := os.read_entire_file_from_path(	fmt.tprintf("%s/base.html", config.layouts_dir), context.allocator)

	result, err := mustache.render_in_layout(
		string(home_tpl),
		data,
		string(base_tpl),
		partials,
	)
	if err != nil {
		fmt.eprintfln("thor: mustache error: %v", err)
		return ""
	}
	return result
}

render_posts_html :: proc(pages: []Page, config: Site_Config) -> string {
	// Group posts by year
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
	// Convert [dynamic]Page_Context slices to []Page_Context for mustache
	year_slices := make([dynamic]Year_Slice)
	defer delete(year_slices)
	for section in year_sections {
		append(&year_slices, Year_Slice{year = section.year, posts = section.posts[:]})
	}

	social_ctx := build_social_context(config)
	defer delete(social_ctx)

	data := map[string]any{
		"title"          = fmt.tprintf("Posts | %s", config.title),
		"year_sections"  = year_slices[:],
		"home_icon"      = ICON_HOME,
		"chevron_up"     = ICON_CHEVRON_UP,
		"year"           = "2026",
		"author"         = config.author,
		"social"         = social_ctx[:],
		"og_url"         = fmt.tprintf("%s/posts/", config.base_url),
		"og_site_name"   = config.title,
		"og_title"       = "Posts",
		"og_description" = config.description,
		"og_type"        = "website",
		"is_article"     = false,
		"og_image"       = fmt.tprintf("%s/avatar.jpg", config.base_url),
	}

	partials := load_partials(config.layouts_dir)

	posts_tpl, _ := os.read_entire_file_from_path(	fmt.tprintf("%s/posts_list.html", config.layouts_dir), context.allocator)
	base_tpl, _ := os.read_entire_file_from_path(	fmt.tprintf("%s/base.html", config.layouts_dir), context.allocator)

	result, err := mustache.render_in_layout(
		string(posts_tpl),
		data,
		string(base_tpl),
		partials,
	)
	if err != nil {
		fmt.eprintfln("thor: mustache error: %v", err)
		return ""
	}
	return result
}

social_icon :: proc(name: string) -> string {
	switch strings.to_lower(name) {
	case "github":
		return ICON_GITHUB
	case "rss":
		return ICON_RSS
	}
	return name
}

format_date :: proc(iso: string) -> string {
	if len(iso) < 10 {
		return iso
	}
	year := iso[:4]
	month_num := (int(iso[5]) - 0x30) * 10 + (int(iso[6]) - 0x30)
	day_num := (int(iso[8]) - 0x30) * 10 + (int(iso[9]) - 0x30)

	if month_num < 1 || month_num > 12 {
		return iso[:10]
	}

	return fmt.aprintf("%d %s %s", day_num, MONTHS[month_num - 1], year)
}

get_year :: proc(iso: string) -> string {
	if len(iso) < 4 {
		return ""
	}
	return iso[:4]
}

sort_pages_by_date :: proc(pages: []Page) {
	for i in 1..<len(pages) {
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
