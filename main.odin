package main

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	// Phase 1: parse flags on empty config to get config_path
	phase1: Site_Config
	flags.parse_or_exit(&phase1, os.args, .Odin)

	path := phase1.config_path
	if path == "" {
		path = "./thor.json"
	}

	// Phase 2: load config file
	config, _ := load_config(path)

	// Phase 3: re-parse flags on loaded config (CLI overrides file values)
	flags.parse_or_exit(&config, os.args, .Odin)

	// Defaults relative to config file's directory
	config_dir := "./"
	if idx := strings.last_index(path, "/"); idx >= 0 {
		config_dir = path[:idx]
	}

	if config.content_dir == "" {
		config.content_dir = fmt.tprintf("%s/content", config_dir)
	}
	if config.output_dir == "" {
		config.output_dir = fmt.tprintf("%s/public", config_dir)
	}
	if config.base_url == "" {
		config.base_url = "http://localhost:8080"
	}

	pages := walk_content(config.content_dir, config.drafts)

	render_site(pages, config)
}
