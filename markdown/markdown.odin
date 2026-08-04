package markdown

import cm "vendor:commonmark"

import "core:encoding/json"
import "core:log"
import "core:strings"

Extension :: enum {
	Emoji,
	Sidenotes,
	Alerts,
	Highlight,
	Sections,
	HeadingIDs,
	DefLists,
	Footnotes,
}

DEFAULT_EXTENSIONS :: bit_set[Extension]{.Emoji, .Sidenotes, .Alerts, .HeadingIDs, .DefLists}

// Caller is responsible for freeing string
process :: proc(
	body: string,
	ext: bit_set[Extension],
	file_path: string,
	allocator := context.allocator,
) -> string {
	side_notes := make(map[string]string)
	margin_notes := make(map[string]string)
	clean_body := body
	if .Sidenotes in ext || .Footnotes in ext {
		clean_body, side_notes, margin_notes = strip_definitions(body)
	}
	if .DefLists in ext {
		clean_body = convert_deflists(clean_body, allocator)
	}
	original_html := cm.markdown_to_html_from_string(clean_body, {.Unsafe})
	html := strings.clone(original_html, allocator)
	cm.free_string(original_html)

	if .Emoji in ext {
		html = expand_emoji(html)
	}
	if .Footnotes in ext {
		html = inject_footnotes(html, side_notes, margin_notes)
	} else if .Sidenotes in ext {
		html = inject_notes(html, side_notes, margin_notes)
	}
	if .Alerts in ext {
		html = inject_alerts(html)
	}
	if .Highlight in ext {
		html = highlight_code(html, file_path)
	}
	if .HeadingIDs in ext {
		html = inject_heading_ids(html)
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
		e, ok := extension_from_name(name)
		if !ok {
			if name != "" {
				log.warnf("unknown extension '%s'", name)
			}
			continue
		}
		result += {e}
	}
	return result
}

// Given a map[Extension]bool, apply it to ext.
apply_extension_config :: proc(ext: ^bit_set[Extension], config: json.Object) {
	for name, val in config {
		// TODO: Silently discards invalid values.
		enabled := val.(json.Boolean) or_continue
		e := extension_from_name(name) or_continue

		if enabled {
			ext^ += {e}
		} else {
			ext^ -= {e}
		}
	}
}

extension_from_name :: proc(name: string) -> (e: Extension, ok: bool) {
	switch name {
	case "emoji":
		e = .Emoji
		ok = true
	case "sidenotes":
		e = .Sidenotes
	case "alerts":
		e = .Alerts
	case "highlight":
		e = .Highlight
	case "sections":
		e = .Sections
	case "heading_ids":
		e = .HeadingIDs
	case "deflists":
		e = .DefLists
	case "footnotes":
		e = .Footnotes
	case:
	// Do nothing
	}

	return e, ok || e != .Emoji
}

// resolve_extension_conflicts resolves mutually exclusive extensions.
// Footnotes and Sidenotes share the same [^id] syntax but render differently;
// if both are enabled (e.g. from defaults + CLI), Footnotes wins.
resolve_extension_conflicts :: proc(ext: ^bit_set[Extension]) {
	if .Footnotes in ext^ && .Sidenotes in ext^ {
		ext^ -= {.Sidenotes}
	}
}

