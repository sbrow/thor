package main

import "base:runtime"
import "core:log"
import "core:os"
import "core:prof/spall"
import "core:sync"
import "core:time"

SPALL :: #config(SPALL, false)

when SPALL {
	spall_ctx: spall.Context
	@(thread_local)
	spall_buffer: spall.Buffer
}

main :: proc() {
	when SPALL {
		ctx, ok := spall.context_create_with_scale("thor.spall", false, 1.0)
		if !ok {
			log.fatal("Failed to create spall trace file")
			os.exit(1)
		}
		spall_ctx = ctx
		defer spall.context_destroy(&spall_ctx)

		spall_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
		defer delete(spall_backing)

		spall_buffer = spall.buffer_create(spall_backing, u32(sync.current_thread_id()))
		defer spall.buffer_destroy(&spall_ctx, &spall_buffer)
	}

	logger_opts: log.Options =
		(log.Default_Console_Logger_Opts - log.Full_Timestamp_Opts - {.Short_File_Path})
	console_logger := log.create_console_logger(.Info, logger_opts)
	context.logger = console_logger
	defer log.destroy_console_logger(console_logger)

	for {
		defer free_all(context.temp_allocator)
		tick := time.tick_now()
		site: Site
		init_site(&site, os.args)
		defer destroy_site(&site)
		// TODO: Make it so this isn't necessary
		context.allocator = site_allocator(&site)
		build_vfs(&site)

		site_load_content(&site)
		render_site(&site)
		log.infof("Built site in %s", time.tick_since(tick))

		(.Watch in site.features) or_break
		time.sleep(5 * time.Second)
	}
}

when SPALL {
	@(instrumentation_enter)
	spall_enter :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) {
		spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
	}

	@(instrumentation_exit)
	spall_exit :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}
}

