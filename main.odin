package main

import "core:log"
import "core:os"

main :: proc() {
	console_logger := log.create_console_logger()
	context.logger = console_logger
	defer log.destroy_console_logger(console_logger)

	site: Site
	init_site(&site, os.args)
	defer destroy_site(&site)

	pages := walk_content(site.content_dir, site.drafts)

	render_site(pages, site)
}

