package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"

import md "markdown"


// Site is the primary workhorse.
Site :: struct {
	arena:               mem.Dynamic_Arena,
	pages:               [dynamic]Page,
	modules:             [dynamic]string,
	vfs:                 VFS,
	title:               string,
	description:         string,
	author:              string,
	base_url:            string,
	config_path:         string,
	content_dir:         string,
	assets_dir:          string,
	output_dir:          string,
	layouts_dir:         string,
	params:              json.Object,
	features:            bit_set[Feature],
	markdown_extensions: bit_set[md.Extension],
}

Feature :: enum {
	Drafts,
	Minify,
	Watch,
}

// Configuration loaded from `thor.json`. Gets folded in to Site before
// Flags
Config_File :: struct {
	title:               string,
	description:         string,
	base_url:            string,
	author:              string,
	content_dir:         string,
	assets_dir:          string,
	output_dir:          string,
	layouts_dir:         string,
	markdown_extensions: json.Value,
	params:              json.Value,
	modules:             json.Value,
}

// Configuration loaded from command line arguments. Gets folded in to Site
// after Config_File
Flags :: struct {
	config_path: string `args:"name=config" usage:"Path to thor.json config file"`,
	base_url:    string `args:"name=base-url" usage:"Site base URL (e.g. https://example.com)"`,
	content_dir: string `args:"name=content" usage:"Path to content directory"`,
	assets_dir:  string `args:"name=assets" usage:"Path to assets directory (CSS, JS, fonts, images)"`,
	output_dir:  string `args:"name=output" usage:"Path to output directory (default: public/)"`,
	layouts_dir: string `args:"name=layouts" usage:"Path to layouts directory"`,
	drafts:      bool `args:"name=drafts" usage:"Include draft pages in the build"`,
	watch:       bool `usage:"Rebuild on file changes (polls every 5 seconds)"`,
	minify:      bool `args:"name=minify" usage:"Minify HTML output and CSS assets"`,
	md_enable:   string `args:"name=ext" usage:"Enable markdown extensions (comma-separated: emoji,sidenotes,alerts,highlight,sections)"`,
	md_disable:  string `args:"name=no-ext" usage:"Disable markdown extensions (comma-separated: emoji,sidenotes,alerts,highlight,sections)"`,
}

init_site :: proc(site: ^Site, args: []string) {
	mem.dynamic_arena_init(&site.arena)
	alloc := site_allocator(site)

	// Set defaults
	site.base_url = "http://localhost:8080"
	site.markdown_extensions = md.DEFAULT_EXTENSIONS

	_flags: Flags
	flags.parse_or_exit(&_flags, args, .Odin, alloc)

	path := _flags.config_path
	if path == "" {
		found, ok := find_config("thor.json")
		if ok {
			path = found
			log.debugf("using config %s", path)
		} else {
			path = "./thor.json"
		}
	}

	config: Config_File
	config_loaded := load_config_file(&config, path, alloc)

	config_dir := "./"
	if idx := strings.last_index(path, "/"); idx >= 0 {
		config_dir = path[:idx]
	}

	if config_loaded {
		site_apply_config(site, config, config_dir)
	} else {
		site_apply_path_defaults(site, config_dir)
	}

	site_apply_cli_flags(site, _flags)
	site.config_path = path
}

load_config_file :: proc(
	config: ^Config_File,
	path: string,
	allocator := context.allocator,
) -> bool {
	data, err := os.read_entire_file_from_path(path, allocator)
	if err != nil {
		return false
	}

	unmarshal_err := json.unmarshal_string(string(data), config, allocator = allocator)
	if unmarshal_err != nil {
		log.warnf("failed to parse %s: %v", path, unmarshal_err)
		return false
	}

	return true
}

site_apply_config :: proc(site: ^Site, config: Config_File, config_dir: string) {
	if config.title != "" do site.title = config.title
	if config.description != "" do site.description = config.description
	if config.author != "" do site.author = config.author
	if config.base_url != "" do site.base_url = config.base_url

	site.content_dir =
		config.content_dir if config.content_dir != "" else fmt.tprintf("%s/content", config_dir)
	site.assets_dir =
		config.assets_dir if config.assets_dir != "" else fmt.tprintf("%s/assets", config_dir)
	site.output_dir =
		config.output_dir if config.output_dir != "" else fmt.tprintf("%s/public", config_dir)
	site.layouts_dir =
		config.layouts_dir if config.layouts_dir != "" else fmt.tprintf("%s/layouts", config_dir)

	if params, ok := config.params.(json.Object); ok {
		site.params = params
	}

	// Apply markdown extensions from config
	if ext_obj, ok := config.markdown_extensions.(json.Object); ok {
		md.apply_extension_config(&site.markdown_extensions, ext_obj)
	}

	if modules_arr, ok := config.modules.(json.Array); ok {
		for &item in modules_arr {
			if s, ok2 := item.(json.String); ok2 {
				append(&site.modules, fmt.tprintf("%s/%s", config_dir, s))
			}
		}
	}
}

site_apply_path_defaults :: proc(site: ^Site, config_dir: string) {
	site.content_dir = fmt.tprintf("%s/content", config_dir)
	site.assets_dir = fmt.tprintf("%s/assets", config_dir)
	site.output_dir = fmt.tprintf("%s/public", config_dir)
	site.layouts_dir = fmt.tprintf("%s/layouts", config_dir)
}

site_apply_cli_flags :: proc(site: ^Site, flags: Flags) {
	if flags.base_url != "" do site.base_url = flags.base_url
	if flags.content_dir != "" do site.content_dir = flags.content_dir
	if flags.assets_dir != "" do site.assets_dir = flags.assets_dir
	if flags.output_dir != "" do site.output_dir = flags.output_dir
	if flags.layouts_dir != "" do site.layouts_dir = flags.layouts_dir

	if flags.drafts {site.features += {.Drafts}}
	if flags.watch {site.features += {.Watch}}
	if flags.minify {site.features += {.Minify}}

	site.markdown_extensions += md.parse_extension_list(flags.md_enable)
	site.markdown_extensions -= md.parse_extension_list(flags.md_disable)
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

