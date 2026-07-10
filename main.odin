package main

import "core:flags"
import "core:fmt"
import "core:os"

Options :: struct {
	base_url:    string `args:"name=base-url" usage:"hostname (and path) to the root, e.g. https://example.com/"`,
	content_dir: string `args:"name=content" usage:"where to look for content files"`,
	output_dir:  string `args:"name=output" usage:"where to export the completed site"`,
	drafts:      bool `args:"name=drafts" usage:"Whether to render draft posts"`,
}

main :: proc() {
	opt: Options

	flags.parse_or_exit(&opt, os.args, .Odin)

	load_default_options(&opt)

	pages := walk_content(opt.content_dir, opt.drafts)

	print_summary(pages)
}

load_default_options :: proc(opt: ^Options) {
	if opt.content_dir == "" {
		opt.content_dir = "./content"
	}

	if opt.output_dir == "" {
		opt.output_dir = "./public"
	}
}

print_summary :: proc(pages: []Page) {
	fmt.printfln("Pages: %d\n", len(pages))

	for page in pages {
		type_label := "post"
		if page.type == .Standalone {
			type_label = "standalone"
		}

		date_short := page.date
		if len(date_short) > 10 {
			date_short = date_short[:10]
		}

		badge := ""
		if page.draft {
			badge = " (draft)"
		} else if page.is_starred {
			badge = " *"
		}

		fmt.printfln(
			"  [%-11s] %-30s %s  %s%s  (%d bytes html)",
			type_label,
			page.title,
			date_short,
			page.permalink,
			badge,
			len(page.body_html),
		)
	}
}

