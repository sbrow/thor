package main

Open_Graph :: struct {
	title:          string,
	type:           string,
	image:          string,
	url:            string,
	description:    string,
	locale:         string,
	site_name:      string,
	is_article:     Maybe(bool),
	published_time: string,
	modified_time:  string,
	section:        string,
}

og_for_site :: proc(site: ^Site) -> Open_Graph {
	og := site.og
	if og.site_name == "" {
		og.site_name = site.title
	}
	if og.description == "" {
		og.description = site.description
	}
	if og.locale == "" {
		og.locale = "en_US"
	}
	return og
}

og_for_page :: proc(site_og: Open_Graph, page: Page) -> Open_Graph {
	og := site_og

	is_article := !page._is_index
	if page.url != "" {
		og.url = page.url
	}
	if page.title != "" {
		og.title = strip_html_tags(page.title, context.temp_allocator)
	} else {
		og.title = og.site_name
	}
	og.type = "article" if is_article else "website"
	og.is_article = is_article
	if page.section != "" {
		og.section = page.section
	}
	if is_article {
		if page.date != "" {
			og.published_time = page.date
		}
		if page.lastmod != "" {
			og.modified_time = page.lastmod
		} else if page.date != "" {
			og.modified_time = page.date
		}
	}

	// Description priority for articles:
	//   page.og.description > page.description > body summary > inherited
	// For non-articles (home, section index), inherited site.og.description
	// is the fallback (matches production behavior — home inherits site
	// description, section index is empty).
	description_set := false
	if page.og.description != "" {
		og.description = page.og.description
		description_set = true
	}
	if !description_set && page.description != "" {
		og.description = page.description
		description_set = true
	}
	if !description_set && is_article && page.body_html != "" {
		og.description = generate_summary(page.body_html)
		description_set = true
	}
	if !description_set {
		if page._is_index && page.section == "" {
			// Home: keep inherited site.og.description.
		} else {
			og.description = ""
		}
	}

	if page.og.title != "" {
		og.title = page.og.title
	}
	if page.og.type != "" {
		og.type = page.og.type
	}
	if page.og.image != "" {
		og.image = page.og.image
	}
	if page.og.url != "" {
		og.url = page.og.url
	}
	if page.og.locale != "" {
		og.locale = page.og.locale
	}
	if page.og.site_name != "" {
		og.site_name = page.og.site_name
	}
	if page.og.published_time != "" {
		og.published_time = page.og.published_time
	}
	if page.og.modified_time != "" {
		og.modified_time = page.og.modified_time
	}
	if page.og.section != "" {
		og.section = page.og.section
	}
	if page.og.is_article != nil {
		og.is_article = page.og.is_article
	}

	return og
}
