package main

import cm "vendor:commonmark"

import "core:fmt"
import "core:strings"

// strip_definitions scans markdown text for footnote definitions ([^id]: text),
// removes them, and returns the cleaned text plus a map of id→definition.
// Handles multi-line definitions with indented continuation lines.
strip_definitions :: proc(body: string) -> (clean_body: string, defs: map[string]string) {
	defs = make(map[string]string)

	lines := strings.split(body, "\n")
	output_lines: [dynamic]string
	defer delete(output_lines)

	i := 0
	for i < len(lines) {
		line := lines[i]

		id, def_text, is_def := parse_def_line(line)
		if !is_def {
			append(&output_lines, line)
			i += 1
			continue
		}

		// Collect definition text (initial line + multi-line continuations)
		def_parts: [dynamic]string
		if def_text != "" {
			append(&def_parts, def_text)
		}

		i += 1
		for i < len(lines) {
			next := lines[i]
			// Stop at blank lines
			if len(next) == 0 {
				break
			}
			// Stop at new footnote definitions
			_, _, is_new_def := parse_def_line(next)
			if is_new_def {
				break
			}
			// Include as continuation (trim indented lines)
			if is_indented(next) {
				append(&def_parts, strings.trim_left(next, " \t"))
			} else {
				append(&def_parts, next)
			}
			i += 1
		}

		defs[id] = strings.join(def_parts[:], "\n")
		delete(def_parts)
	}

	clean_body = strings.join(output_lines[:], "\n")
	return
}

// parse_def_line checks if a line is a footnote definition: [^id]: text
parse_def_line :: proc(line: string) -> (id: string, text: string, ok: bool) {
	if len(line) < 5 || line[0] != '[' || line[1] != '^' {
		return
	}

	close := strings.index(line[2:], "]")
	if close < 0 {
		return
	}
	close += 2

	if close + 1 >= len(line) || line[close + 1] != ':' {
		return
	}

	id = line[2:close]
	text = strings.trim_left(line[close + 2:], " \t")
	ok = true
	return
}

is_indented :: proc(line: string) -> bool {
	if len(line) == 0 {
		return false
	}
	return line[0] == ' ' || line[0] == '\t'
}

// inject_sidenotes finds [^id] references in rendered HTML and replaces them
// with sidenote markup. Each definition is rendered through cmark separately.
inject_sidenotes :: proc(html: string, defs: map[string]string) -> string {
	if len(defs) == 0 {
		return html
	}

	parts: [dynamic]string
	defer delete(parts)

	remaining := html

	for {
		pos := strings.index(remaining, "[^")
		if pos < 0 {
			append(&parts, remaining)
			break
		}

		// Append text before [^
		append(&parts, remaining[:pos])

		close := strings.index(remaining[pos + 2:], "]")
		if close < 0 {
			append(&parts, remaining[pos:])
			break
		}

		id := remaining[pos + 2 : pos + 2 + close]
		ref_end := pos + 2 + close + 1

		def_text, found := defs[id]
		if !found {
			// No definition found, leave as literal text
			append(&parts, remaining[pos:ref_end])
			remaining = remaining[ref_end:]
			continue
		}

		// Render definition through cmark for markdown support
		def_html := cm.markdown_to_html_from_string(def_text, {.Unsafe})
		def_html = strip_p_tags(def_html)

		sidenote := fmt.aprintf(
			`<label for="fn-%s" class="margin-toggle sidenote-number"></label><input type="checkbox" id="fn-%s" class="margin-toggle"><span class="sidenote">%s</span>`,
			id,
			id,
			def_html,
		)
		append(&parts, sidenote)

		remaining = remaining[ref_end:]
	}

	return strings.join(parts[:], "")
}

// strip_p_tags removes surrounding <p></p> if the HTML is a single paragraph.
strip_p_tags :: proc(html: string) -> string {
	s := html
	if len(s) > 0 && s[len(s) - 1] == '\n' {
		s = s[:len(s) - 1]
	}
	if strings.has_prefix(s, "<p>") && strings.has_suffix(s, "</p>") {
		return s[3:len(s) - 4]
	}
	return s
}
