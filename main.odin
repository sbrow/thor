package main

import "core:os"

main :: proc() {
	site: Site
	init_site(&site, os.args)

	pages := walk_content(site.content_dir, site.drafts)

	render_site(pages, site)
}

