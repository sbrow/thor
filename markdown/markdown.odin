package markdown

import cm "vendor:commonmark"

import "core:encoding/json"
import "core:strings"

Extension :: enum {
	Emoji,
	Sidenotes,
	Alerts,
	Highlight,
	Sections,
}

DEFAULT_EXTENSIONS :: bit_set[Extension]{.Emoji, .Sidenotes, .Alerts}

process :: proc(body: string, ext: bit_set[Extension], file_path: string) -> string {
	side_notes := make(map[string]string)
	margin_notes := make(map[string]string)
	clean_body := body
	if .Sidenotes in ext {
		clean_body, side_notes, margin_notes = strip_definitions(body)
	}
	html := cm.markdown_to_html_from_string(clean_body, {.Unsafe})
	if .Emoji in ext {
		html = expand_emoji(html)
	}
	if .Sidenotes in ext {
		html = inject_notes(html, side_notes, margin_notes)
	}
	if .Alerts in ext {
		html = inject_alerts(html)
	}
	if .Highlight in ext {
		html = highlight_code(html, file_path)
	}
	if .Sections in ext {
		html = wrap_sections(html)
	}
	return html
}

// Convert a ',' separated list of case-insensitive extension names to a bit set.
parse_extension_list :: proc(s: string) -> (result: bit_set[Extension]) {
	for part in strings.split(s, ",", allocator = context.temp_allocator) {
		name := strings.to_lower(strings.trim_space(part), allocator = context.temp_allocator)
		switch name {
		case "emoji":
			result += {.Emoji}
		case "sidenotes":
			result += {.Sidenotes}
		case "alerts":
			result += {.Alerts}
		case "highlight":
			result += {.Highlight}
		case "sections":
			result += {.Sections}
		}
	}
	return result
}

// Given a map[Extension]bool, apply it to ext.
apply_extension_config :: proc(ext: ^bit_set[Extension], config: json.Object) {
	for name, val in config {
		// TODO: Silently discards invalid values.
		enabled := val.(json.Boolean) or_continue
		switch name {
		case "emoji":
			if enabled {ext^ += {.Emoji}} else {ext^ -= {.Emoji}}
		case "sidenotes":
			if enabled {ext^ += {.Sidenotes}} else {ext^ -= {.Sidenotes}}
		case "alerts":
			if enabled {ext^ += {.Alerts}} else {ext^ -= {.Alerts}}
		case "highlight":
			if enabled {ext^ += {.Highlight}} else {ext^ -= {.Highlight}}
		case "sections":
			if enabled {ext^ += {.Sections}} else {ext^ -= {.Sections}}
		}
	}
}

