package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"


Site :: struct {
	arena:       mem.Dynamic_Arena,
	title:       string,
	description: string,
	author:      string,
	base_url:    string,
	config_path: string,
	content_dir: string,
	static_dir:  string,
	assets_dir:  string,
	output_dir:  string,
	layouts_dir: string,
	params:      json.Value,
	features:    bit_set[Feature],
}

Feature :: enum {
	Sections,
	Drafts,
	Minify,
	Watch,
}

Flags :: struct {
	config_path: string `args:"name=config"`,
	title:       string,
	description: string,
	base_url:    string `args:"name=base-url"`,
	content_dir: string `args:"name=content"`,
	static_dir:  string `args:"name=static"`,
	assets_dir:  string `args:"name=assets"`,
	output_dir:  string `args:"name=output"`,
	layouts_dir: string,
	author:      string,
	params:      json.Value,
	sectionate:  bool `args:"name=sections"`,
	drafts:      bool `args:"name=drafts"`,
	watch:       bool,
	minify:      bool `args:"name=minify"`,
}

init_site :: proc(site: ^Site, args: []string) {
	_flags: Flags
	mem.dynamic_arena_init(&site.arena, alignment = 64) // FIXME: This is a hack
	alloc := site_allocator(site)
	flags.parse_or_exit(&_flags, args, .Odin, alloc)

	path := _flags.config_path
	if path == "" {
		found, ok := find_config("thor.json")
		if ok {
			path = found
			log.debugf("thor: using config %s", path)
		} else {
			path = "./thor.json"
		}
	}

	cfg, cfg_ok := load_site_config(path, alloc)
	if cfg_ok {
		merge_flags(&cfg, _flags)
	} else {
		cfg = _flags
	}

	site_apply_flags(site, cfg)

	// Determine config file's directory for relative defaults
	config_dir := "./"
	if idx := strings.last_index(path, "/"); idx >= 0 {
		config_dir = path[:idx]
	}

	// Hardcoded defaults (lowest precedence)
	// TODO: Probably shouldn't use temp allocator here?
	if site.content_dir == "" {
		site.content_dir = fmt.tprintf("%s/content", config_dir)
	}
	if site.static_dir == "" {
		site.static_dir = fmt.tprintf("%s/static", config_dir)
	}
	if site.assets_dir == "" {
		site.assets_dir = fmt.tprintf("%s/assets", config_dir)
	}
	if site.output_dir == "" {
		site.output_dir = fmt.tprintf("%s/public", config_dir)
	}
	if site.layouts_dir == "" {
		site.layouts_dir = fmt.tprintf("%s/layouts", config_dir)
	}
	if site.base_url == "" {
		site.base_url = "http://localhost:8080"
	}
}

load_site_config :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	config: Flags,
	ok: bool,
) {
	data, err := os.read_entire_file_from_path(path, allocator)
	if err != nil {
		return
	}

	unmarshal_err := json.unmarshal_string(string(data), &config, allocator = allocator)
	if unmarshal_err != nil {
		log.warnf("thor: failed to parse %s: %v", path, unmarshal_err)
		return
	}

	ok = true
	return
}

merge_flags :: proc(config: ^Flags, flags: Flags) {
	if flags.base_url != "" {
		config.base_url = flags.base_url
	}
	if flags.content_dir != "" {
		config.content_dir = flags.content_dir
	}
	if flags.static_dir != "" {
		config.static_dir = flags.static_dir
	}
	if flags.assets_dir != "" {
		config.assets_dir = flags.assets_dir
	}
	if flags.output_dir != "" {
		config.output_dir = flags.output_dir
	}
	if flags.drafts {
		config.drafts = true
	}
	if flags.watch {
		config.watch = true
	}
	if flags.sectionate {
		config.sectionate = true
	}
	if flags.minify {
		config.minify = true
	}
	config.config_path = flags.config_path
}

site_apply_flags :: proc(site: ^Site, flags: Flags) {
	site.title = flags.title
	site.description = flags.description
	site.author = flags.author
	site.base_url = flags.base_url
	site.config_path = flags.config_path
	site.content_dir = flags.content_dir
	site.static_dir = flags.static_dir
	site.assets_dir = flags.assets_dir
	site.output_dir = flags.output_dir
	site.layouts_dir = flags.layouts_dir
	site.params = flags.params

	if flags.sectionate {site.features += {.Sections}}
	if flags.drafts {site.features += {.Drafts}}
	if flags.watch {site.features += {.Watch}}
	if flags.minify {site.features += {.Minify}}
}

site_allocator :: proc(site: ^Site) -> mem.Allocator {
	return mem.dynamic_arena_allocator(&site.arena)
}

destroy_site :: proc(site: ^Site) {
	mem.dynamic_arena_destroy(&site.arena)
}

find_config :: proc(filename: string) -> (path: string, ok: bool) {
	dir, _ := os.get_working_directory(context.temp_allocator)

	for {
		candidate := fmt.tprintf("%s/%s", dir, filename)
		if os.exists(candidate) {
			path = candidate
			ok = true
			return
		}

		idx := strings.last_index(dir, "/")
		if idx <= 0 {
			return
		}
		dir = dir[:idx]
	}
}

