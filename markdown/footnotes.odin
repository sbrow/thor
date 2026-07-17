package markdown

import cm "vendor:commonmark"

import "core:fmt"
import "core:strings"

Note_Kind :: enum {
	Sidenote,
	Marginnote,
}

// strip_definitions scans markdown text for note definitions ([^id]: text for
// sidenotes, [*id]: text for marginnotes), removes them, and returns the cleaned
// text plus separate maps of id->definition for each kind.
// Handles multi-line definitions with indented continuation lines.
strip_definitions :: proc(
	body: string,
) -> (
	clean_body: string,
	sn_defs, mn_defs: map[string]string,
) {
	lines := strings.split(body, "\n")
	defer delete(lines)

	out_sb := strings.builder_make()
	defer strings.builder_destroy(&out_sb)

	i := 0
	for i < len(lines) {
		line := lines[i]

		id, def_text, kind, is_def := parse_def_line(line)
		if !is_def {
			if strings.builder_len(out_sb) > 0 {
				strings.write_string(&out_sb, "\n")
			}
			strings.write_string(&out_sb, line)
			i += 1
			continue
		}

		def_sb := strings.builder_make()
		if def_text != "" {
			strings.write_string(&def_sb, def_text)
		}

		i += 1
		for i < len(lines) {
			next := lines[i]
			if len(next) == 0 {
				break
			}
			_, _, _, is_new_def := parse_def_line(next)
			if is_new_def {
				break
			}
			if strings.builder_len(def_sb) > 0 {
				strings.write_string(&def_sb, "\n")
			}
			if is_indented(next) {
				strings.write_string(&def_sb, strings.trim_left(next, " \t"))
			} else {
				strings.write_string(&def_sb, next)
			}
			i += 1
		}

		joined := strings.clone(strings.to_string(def_sb))
		strings.builder_destroy(&def_sb)

		if kind == .Marginnote {
			mn_defs[id] = joined
		} else {
			sn_defs[id] = joined
		}
	}

	clean_body = strings.clone(strings.to_string(out_sb))
	return
}

// parse_def_line checks if a line is a note definition: [^id]: text (sidenote)
// or [*id]: text (marginnote).
parse_def_line :: proc(line: string) -> (id: string, text: string, kind: Note_Kind, ok: bool) {
	if len(line) < 5 || line[0] != '[' {
		return
	}

	if line[1] == '^' {
		kind = .Sidenote
	} else if line[1] == '*' {
		kind = .Marginnote
	} else {
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

// inject_notes finds [^id] (sidenote) and [*id] (marginnote) references in
// rendered HTML and replaces them with the appropriate margin markup. Each
// definition is rendered through cmark separately.
inject_notes :: proc(html: string, sn_defs, mn_defs: map[string]string) -> string {
	if len(sn_defs) == 0 && len(mn_defs) == 0 {
		return html
	}

	parts: strings.Builder
	strings.builder_init_len(&parts, 0) // TODO: Set a reasonable default
	defer strings.builder_destroy(&parts)

	remaining := html

	for {
		sn_pos := strings.index(remaining, "[^")
		mn_pos := strings.index(remaining, "[*")

		is_margin := mn_pos >= 0 && (sn_pos < 0 || mn_pos < sn_pos)
		pos := sn_pos
		if is_margin {
			pos = mn_pos
		}
		if pos < 0 {
			strings.write_string(&parts, remaining)
			break
		}

		// Append text before the reference
		strings.write_string(&parts, remaining[:pos])

		close := strings.index(remaining[pos + 2:], "]")
		if close < 0 {
			strings.write_string(&parts, remaining[pos:])
			break
		}

		id := remaining[pos + 2:pos + 2 + close]
		ref_end := pos + 2 + close + 1

		defs := sn_defs
		if is_margin {
			defs = mn_defs
		}
		def_text, found := defs[id]
		if !found {
			// No definition found, leave as literal text
			strings.write_string(&parts, remaining[pos:ref_end])
			remaining = remaining[ref_end:]
			continue
		}

		// Render definition through cmark for markdown support
		def_html := cm.markdown_to_html_from_string(def_text, {.Unsafe})
		def_html = strip_p_tags(def_html)

		note: string
		defer delete(note)
		if is_margin {
			note = fmt.aprintf(
				`<label for="mn-%s" class="margin-toggle"></label><input type="checkbox" id="mn-%s" class="margin-toggle"><span class="marginnote">%s</span>`,
				id,
				id,
				def_html,
			)
		} else {
			note = fmt.aprintf(
				`<label for="fn-%s" class="margin-toggle sidenote-number"></label><input type="checkbox" id="fn-%s" class="margin-toggle"><span class="sidenote">%s</span>`,
				id,
				id,
				def_html,
			)
		}
		strings.write_string(&parts, note)

		remaining = remaining[ref_end:]
	}

	return strings.to_string(parts)
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

