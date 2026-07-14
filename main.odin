package main

import "core:log"
import "core:os"
import "core:time"

main :: proc() {
	console_logger := log.create_console_logger()
	context.logger = console_logger
	defer log.destroy_console_logger(console_logger)

	for {
		defer free_all(context.temp_allocator)
		site: Site
		init_site(&site, os.args)
		defer destroy_site(&site)
		// TODO: Make it so this isn't necessary
		context.allocator = site_allocator(&site)

		pages := walk_content(&site)
		render_site(pages, site)

		if !site.watch {
			break
		}
		time.sleep(5 * time.Second)
	}
}

