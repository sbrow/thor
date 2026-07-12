package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

Social_Link :: struct {
	name: string,
	url:  string,
}

Site_Config :: struct {
	config_path: string `args:"name=config"`,
	title:       string,
	description: string,
	base_url:    string `args:"name=base-url"`,
	content_dir: string `args:"name=content"`,
	output_dir:  string `args:"name=output"`,
	author:      string,
	social:      []Social_Link,
	drafts:      bool   `args:"name=drafts"`,
}

load_config :: proc(path: string) -> (config: Site_Config, ok: bool) {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return
	}

	value, parse_err := json.parse_string(string(data), spec = .JSON)
	if parse_err != nil {
		fmt.eprintfln("thor: failed to parse %s: %v", path, parse_err)
		return
	}
	defer json.destroy_value(value)

	obj, obj_ok := value.(json.Object)
	if !obj_ok {
		return
	}

	config.title       = json_get_string(obj, "title")
	config.description = json_get_string(obj, "description")
	config.base_url    = json_get_string(obj, "base_url")
	config.content_dir = json_get_string(obj, "content_dir")
	config.output_dir  = json_get_string(obj, "output_dir")
	config.author      = json_get_string(obj, "author")

	if v, found := obj["social"]; found {
		if arr, arr_ok := v.(json.Array); arr_ok {
			social: [dynamic]Social_Link
			for elem in arr {
				if elem_obj, eo_ok := elem.(json.Object); eo_ok {
					link := Social_Link{}
					link.name = json_get_string(elem_obj, "name")
					link.url  = json_get_string(elem_obj, "url")
					append(&social, link)
				}
			}
			config.social = social[:]
		}
	}

	ok = true
	return
}
