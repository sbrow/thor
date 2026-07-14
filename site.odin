package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"

Site :: struct {
	// TODO: User can still technically try to set this
	arena:       mem.Dynamic_Arena `args:"hidden"`,
	config_path: string `args:"name=config"`,
	title:       string,
	description: string,
	base_url:    string `args:"name=base-url"`,
	content_dir: string `args:"name=content"`,
	static_dir:  string `args:"name=static"`,
	output_dir:  string `args:"name=output"`,
	layouts_dir: string,
	author:      string,
	params:      json.Value,
	sectionate:  bool,
	drafts:      bool `args:"name=drafts"`,
	watch:       bool,
}

init_site :: proc(site: ^Site, args: []string) {
	_flags: Site
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

	if load_site_config(site, path, alloc) {
		site_merge(site, _flags)
	} else {
		_flags.arena = site.arena
		site^ = _flags
	}

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
	config: ^Site,
	path: string,
	allocator := context.allocator,
) -> (
	ok: bool,
) {
	data, err := os.read_entire_file_from_path(path, allocator)
	if err != nil {
		return
	}

	unmarshal_err := json.unmarshal_string(string(data), config, allocator = allocator)
	if unmarshal_err != nil {
		log.warnf("thor: failed to parse %s: %v", path, unmarshal_err)
		return
	}

	ok = true
	return
}

site_merge :: proc(config: ^Site, flags: Site) {
	if flags.base_url != "" {
		config.base_url = flags.base_url
	}
	if flags.content_dir != "" {
		config.content_dir = flags.content_dir
	}
	if flags.static_dir != "" {
		config.static_dir = flags.static_dir
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
	config.config_path = flags.config_path
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

