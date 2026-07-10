package main

import "core:encoding/json"
import "core:fmt"
import "core:strings"

Frontmatter :: struct {
	title:       string,
	date:        string,
	publishDate: string,
	draft:       bool,
	isStarred:   bool,
	menu:        string,
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
		fmt.eprintfln("thor: failed to parse frontmatter JSON: %v", err)
		return
	}
	defer json.destroy_value(value)

	obj, ok2 := value.(json.Object)
	if !ok2 {
		return
	}

	fm.title = json_get_string(obj, "title")
	fm.date = json_get_string(obj, "date")
	fm.publishDate = json_get_string(obj, "publishDate")
	fm.draft = json_get_bool(obj, "draft")
	fm.isStarred = json_get_bool(obj, "isStarred")
	fm.menu = json_get_string(obj, "menu")

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

