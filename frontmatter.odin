package main

import "core:encoding/json"
import "core:fmt"
import "core:strings"

Frontmatter :: struct {
	title:       string,
	description: string,
	date:        string,
	lastmod:     string,
	publishDate: string,
	menu:        string,
	layout:      string,
	og:          Open_Graph,
	draft:       bool,
	isStarred:   bool,
}

// parse_frontmatter splits raw file content into a Frontmatter struct and the
// remaining markdown body. The frontmatter is a JSON object delimited by { }
// at the start of the file.
parse_frontmatter :: proc(content: string) -> (fm: Frontmatter, body: string, ok: bool) {
	body = content

	if !strings.has_prefix(content, "{\n") {
		return
	}
	end := strings.index(content, "\n}\n")
	if end < 0 {
		return
	} else {
		end += 2
	}

	json_str := content[:end + 1]
	body = strings.trim_left(content[end + 1:], " \t\r\n")

	value, err := json.parse_string(json_str, spec = .JSON)
	if err != nil {
		fmt.eprintfln("failed to parse frontmatter JSON: %v", err)
		return
	}
	defer json.destroy_value(value)

	obj, ok2 := value.(json.Object)
	if !ok2 {
		return
	}

	fm.title       = json_get_string(obj, "title")
	fm.description = json_get_string(obj, "description")
	fm.date        = json_get_string(obj, "date")
	fm.lastmod     = json_get_string(obj, "lastmod")
	fm.publishDate = json_get_string(obj, "publishDate")
	fm.draft = json_get_bool(obj, "draft")
	fm.isStarred = json_get_bool(obj, "isStarred")
	fm.menu = json_get_string(obj, "menu")
	fm.layout = json_get_string(obj, "layout")
	fm.og = json_get_open_graph(obj, "og")

	ok = true
	return
}

json_get_string :: proc(obj: json.Object, key: string) -> string {
	if v, ok := obj[key]; ok {
		if s, ok2 := v.(json.String); ok2 {
			return strings.clone(s)
		}
	}
	return ""
}

json_get_bool :: proc(obj: json.Object, key: string) -> bool {
	if v, ok := obj[key]; ok {
		if b, ok2 := v.(json.Boolean); ok2 {
			return b
		}
	}
	return false
}

json_get_open_graph :: proc(obj: json.Object, key: string) -> Open_Graph {
	og: Open_Graph
	if v, ok := obj[key]; ok {
		if inner, ok2 := v.(json.Object); ok2 {
			og.title          = json_get_string(inner, "title")
			og.type           = json_get_string(inner, "type")
			og.image          = json_get_string(inner, "image")
			og.url            = json_get_string(inner, "url")
			og.description    = json_get_string(inner, "description")
			og.locale         = json_get_string(inner, "locale")
			og.site_name      = json_get_string(inner, "site_name")
			og.published_time = json_get_string(inner, "published_time")
			og.modified_time  = json_get_string(inner, "modified_time")
			og.section        = json_get_string(inner, "section")
		}
	}
	return og
}

