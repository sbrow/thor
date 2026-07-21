package main

import "mustache"

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:time"
import "core:time/datetime"

Page_Context :: struct {
	permalink: string,
	title:     string,
	starred:   bool,
	date:      string,
	year:      string,
}

Base_Data :: struct {
	now:         datetime.DateTime,
	params:      json.Value,
	body:        string,
	title:       string,
	description: string,
	og:          Open_Graph,
}

Page_Data :: struct {
	using base: Base_Data,
	page_title: string,
	date:       string,
}

Home_Data :: struct {
	using base: Base_Data,
	pages:      [dynamic]Page_Context,
}

Section_Data :: struct {
	using base: Base_Data,
	page_title: string,
	posts:      [dynamic]Page_Context,
}

build_page_context :: proc(page: Page) -> Page_Context {
	return Page_Context {
		permalink = page.permalink,
		title = page.title,
		starred = page.is_starred,
		date = page.date,
		year = get_year(page.date),
	}
}

load_template :: proc(vfs: ^VFS, virtual_path: string) -> mustache.Template {
	entry, data, ok := vfs_get_entry(vfs, virtual_path)
	if !ok {
		log.fatalf("template %s not found", virtual_path)
		os.exit(1)
	}
	source := string(data)
	tpl, err := mustache.parse(source, entry.fs_path)
	if err != nil {
		b := mustache.body(err)
		log.errorf(
			"%s",
			mustache.format_error(
				entry.fs_path,
				source,
				b.pos,
				b.msg,
				colorize = mustache.should_colorize(),
			),
		)
		os.exit(1)
	}
	return tpl
}

get_template :: proc(
	vfs: ^VFS,
	layout: string,
	cache: ^map[string]mustache.Template,
) -> mustache.Template {
	chain: [4]string
	n := 0
	chain[n] = layout; n += 1
	if strings.has_suffix(layout, "_index") && layout != "section_index" {
		chain[n] = "section_index"; n += 1
	}
	if layout != "page" && layout != "base" {
		chain[n] = "page"; n += 1
	}
	if layout != "base" {
		chain[n] = "base"; n += 1
	}

	for i in 0 ..< n {
		candidate := chain[i]
		if cached, ok := cache[candidate]; ok {
			return cached
		}
		virtual := fmt.tprintf("layouts/%s.html", candidate)
		if _, ok := vfs_get(vfs, virtual); ok {
			tpl := load_template(vfs, virtual)
			cache[candidate] = tpl
			return tpl
		}
		if candidate != chain[n - 1] {
			log.debugf("template %s not found, falling back", virtual)
		}
	}

	log.errorf("base.html not found in VFS")
	return mustache.Template{}
}

capitalize :: proc(s: string) -> string {
	if len(s) == 0 {
		return s
	}
	if s[0] >= 'a' && s[0] <= 'z' {
		return fmt.aprintf("%c%s", s[0] - 32, s[1:])
	}
	return s
}

render_template :: proc(
	content_tpl: mustache.Template,
	data: any,
	partials: map[string]mustache.Template,
) -> string {
	result, err := mustache.render(content_tpl, data, partials)
	if err != nil {
		log.errorf(
			"%s",
			mustache.format_render_error(err, content_tpl, colorize = mustache.should_colorize()),
		)
		return ""
	}
	return result
}

render_site :: proc(site: ^Site) {
	pages := site.pages[:]
	sort_pages_by_date(pages)

	// Load shared resources
	partials := load_partials(&site.vfs)
	partials["base"] = load_template(&site.vfs, "layouts/base.html")

	template_cache: map[string]mustache.Template
	defer delete(template_cache)

	now, ok := time.time_to_datetime(time.now())
	assert(ok)

	// Build base data once
	base := Base_Data {
		now         = now,
		params      = site.params,
		description = site.description,
		og          = site.og,
	}

	// Find home page
	home: Page
	has_home := false
	for page in pages {
		if page.section == "" && page._is_index {
			home = page
			has_home = true
			break
		}
	}

	// Collect sections
	sections := make(map[string]bool)
	defer delete(sections)
	for page in pages {
		if page.section != "" {
			sections[page.section] = true
		}
	}

	// Render individual content pages (skip all index pages)
	for page in pages {
		if page._is_index {
			continue
		}
		tpl := get_template(&site.vfs, page.layout, &template_cache)
		html := render_page_html(page, site, tpl, partials, base)
		if .Minify in site.features {
			html = minify_html(html)
		}
		write_page(site.output_dir, page.permalink, html)
	}

	// Render section index pages
	for section in sections {
		section_index: Page
		has_section_index := false
		for page in pages {
			if page.section == section && page._is_index {
				section_index = page
				has_section_index = true
				break
			}
		}

		layout := fmt.tprintf("%s_index", section)
		section_tpl := get_template(&site.vfs, layout, &template_cache)
		html := render_section(
			site,
			section,
			section_index,
			has_section_index,
			section_tpl,
			partials,
			base,
		)
		if .Minify in site.features {
			html = minify_html(html)
		}
		write_page(site.output_dir, fmt.aprintf("/%s/", section), html)
	}

	// Render home page
	if has_home {
		home_tpl := get_template(&site.vfs, "home", &template_cache)
		home_html := render_home_html(home, site, home_tpl, partials, base)
		if .Minify in site.features {
			home_html = minify_html(home_html)
		}
		write_file(fmt.tprintf("%s/index.html", site.output_dir), home_html)
	}

	// Generate RSS feed
	rss := generate_rss(site)
	write_file(fmt.tprintf("%s/index.xml", site.output_dir), rss)

	// Generate sitemap
	sitemap := generate_sitemap(site)
	write_file(fmt.tprintf("%s/sitemap.xml", site.output_dir), sitemap)

	// Copy and optionally minify assets directory
	copy_assets_dir(&site.vfs, site.output_dir, site.features)

	// Generate robots.txt
	robots := fmt.aprintf("User-agent: *\nAllow: /\nSitemap: %s/sitemap.xml\n", site.base_url)
	write_file(fmt.tprintf("%s/robots.txt", site.output_dir), robots)

	total := len(pages) + len(sections)
	if !has_home {
		total += 1
	}
	fmt.printfln("Rendered %d pages to %s", total, site.output_dir)
}

render_page_html :: proc(
	page: Page,
	site: ^Site,
	content_tpl: mustache.Template,
	partials: map[string]mustache.Template,
	base: Base_Data,
) -> string {
	is_article := page.section != ""
	data := Page_Data {
		base = base,
	}
	data.title = fmt.tprintf("%s | %s", page.title, site.title)
	data.page_title = page.title
	data.body = page.body_html
	data.date = page.date
	data.og = og_for_page(site.og, page)
	return render_template(content_tpl, data, partials)
}

render_home_html :: proc(
	home: Page,
	site: ^Site,
	content_tpl: mustache.Template,
	partials: map[string]mustache.Template,
	base: Base_Data,
) -> string {
	list_pages := make([dynamic]Page_Context)
	defer delete(list_pages)
	for page in site.pages {
		if page._is_index {
			continue
		}
		append(&list_pages, build_page_context(page))
	}

	data := Home_Data {
		base = base,
	}
	data.title = site.title
	data.body = home.body_html
	data.pages = list_pages
	data.og = og_for_page(site.og, home)
	return render_template(content_tpl, data, partials)
}

render_section :: proc(
	site: ^Site,
	section: string,
	section_index: Page,
	has_index: bool,
	content_tpl: mustache.Template,
	partials: map[string]mustache.Template,
	base: Base_Data,
) -> string {
	posts := make([dynamic]Page_Context)
	defer delete(posts)
	for page in site.pages {
		if page.section != section || page._is_index {
			continue
		}
		append(&posts, build_page_context(page))
	}

	data := Section_Data {
		base = base,
	}
	if has_index {
		data.body = section_index.body_html
		data.page_title = section_index.title
		data.title = fmt.tprintf("%s | %s", section_index.title, site.title)
		data.og = og_for_page(site.og, section_index)
	} else {
		data.page_title = capitalize(section)
		data.title = fmt.tprintf("%s | %s", capitalize(section), site.title)
		data.og.title = capitalize(section)
		data.og.description = ""
		data.og.url = fmt.tprintf("%s/%s/", site.base_url, section)
		data.og.type = "website"
		data.og.is_article = false
	}
	data.posts = posts
	return render_template(content_tpl, data, partials)
}

load_partials :: proc(vfs: ^VFS) -> map[string]mustache.Template {
	partials: map[string]mustache.Template
	prefix := "layouts/partials/"
	for virtual_path, entry in vfs.files {
		if !strings.has_prefix(virtual_path, prefix) {
			continue
		}
		if !strings.has_suffix(virtual_path, ".html") {
			continue
		}

		stripped := virtual_path[len(prefix):]
		key := stripped[:len(stripped) - len(".html")]

		data := vfs_entry_data(entry) or_continue
		source := string(data)
		tpl, err := mustache.parse(source, entry.fs_path)
		if err != nil {
			b := mustache.body(err)
			log.errorf(
				"%s",
				mustache.format_error(
					entry.fs_path,
					source,
					b.pos,
					b.msg,
					colorize = mustache.should_colorize(),
				),
			)
			os.exit(1)
		}
		partials[key] = tpl
	}
	return partials
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
		log.errorf("cannot create %s: %v", dir, err)
		return
	}

	file_path := fmt.tprintf("%s/index.html", dir)
	write_file(file_path, html)
}

write_file :: proc(path: string, html: string) {
	if err := os.write_entire_file_from_string(path, html); err != nil {
		log.errorf("cannot write %s: %v", path, err)
	}
}

