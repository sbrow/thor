package main

import "core:fmt"

Open_Graph :: struct {
	title:          string,
	type:           string,
	image:          string,
	url:            string,
	description:    string,
	locale:         string,
	site_name:      string,
	is_article:     bool,
	published_time: string,
	modified_time:  string,
	section:        string,
}

og_init :: proc(site: Site) -> Open_Graph {
	return {
		site_name = site.title,
		description = site.description,
		image = fmt.tprintf("%s/avatar.jpg", site.base_url),
		locale = "en_US",
	}
}

og_for_page :: proc(site: Site, page: Page, base: Open_Graph) -> Open_Graph {
	og := base
	is_article := page.section != ""
	og.url = page.url
	og.title = strip_html_tags(page.title, context.temp_allocator)
	og.type = "article" if is_article else "website"
	og.is_article = is_article
	og.section = page.section
	og.published_time = page.date

	return og
}

