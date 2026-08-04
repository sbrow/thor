package markdown

import cm "vendor:commonmark"

import "core:strings"

// DefList_Entry represents a single term-definition pair in a definition list.
DefList_Entry :: struct {
	term:       string,
	definition: string,
}

// convert_deflists scans markdown text for definition list patterns and
// converts them to <dl><dt><dd> HTML blocks before cmark processing.
//
// A definition line starts with optional whitespace followed by a colon and
// a space. The term is the nearest preceding non-blank line (immediately or
// within one blank line). Consecutive term+definition pairs are grouped into
// a single <dl> block.
//
// Terms and definitions are rendered through cmark individually so that
// inline markdown (code, links, emphasis) is processed.
convert_deflists :: proc(body: string, allocator := context.allocator) -> string {
	lines := strings.split(body, "\n", allocator = context.temp_allocator)

	sb := strings.builder_make(context.temp_allocator)

	first := true
	need_blank := false

	i := 0
	for i < len(lines) {
		entries, matched, next := try_match_deflist(lines, i)
		if matched {
			html := render_deflist(entries)
			if !first {
				strings.write_string(&sb, "\n\n")
			}
			strings.write_string(&sb, html)
			first = false
			need_blank = true
			i = next
			continue
		}

		if need_blank {
			strings.write_string(&sb, "\n\n")
			need_blank = false
		} else if !first {
			strings.write_string(&sb, "\n")
		}
		strings.write_string(&sb, lines[i])
		first = false
		i += 1
	}

	return strings.clone(strings.to_string(sb), allocator)
}

// try_match_deflist attempts to match a definition list group starting at
// lines[start]. A group is one or more term+definition pairs. Returns the
// matched entries, whether a match was found, and the index past the group.
try_match_deflist :: proc(
	lines: []string,
	start: int,
) -> (
	entries: [dynamic]DefList_Entry,
	ok: bool,
	end: int,
) {
	entries = make([dynamic]DefList_Entry, 0, allocator = context.temp_allocator)
	end = start

	i := start
	for i < len(lines) {
		// A term must be non-blank and not itself a def line
		if is_blank_line(lines[i]) || is_def_line(lines[i]) {
			break
		}

		// Look for a def line: immediately after or with one blank line
		def_idx := i + 1
		if def_idx < len(lines) && is_blank_line(lines[def_idx]) {
			def_idx += 1
		}

		if def_idx >= len(lines) || !is_def_line(lines[def_idx]) {
			break
		}

		// Found a term + def pair
		append(
			&entries,
			DefList_Entry {
				term = strings.trim_space(lines[i]),
				definition = def_content(lines[def_idx]),
			},
		)
		i = def_idx + 1

		// After a pair, check if another pair follows (optionally
		// separated by one blank line). If so, continue the group.
		// If not, break without consuming the blank line.
		if i < len(lines) && is_blank_line(lines[i]) {
			after_blank := i + 1
			if after_blank < len(lines) &&
			   !is_blank_line(lines[after_blank]) &&
			   !is_def_line(lines[after_blank]) {
				// Check whether a def follows this potential term
				check_def := after_blank + 1
				if check_def < len(lines) && is_blank_line(lines[check_def]) {
					check_def += 1
				}
				if check_def < len(lines) && is_def_line(lines[check_def]) {
					i = after_blank
					continue
				}
			}
			break
		}
	}

	if len(entries) > 0 {
		ok = true
		end = i
	}
	return
}

// is_def_line returns true if the line is a definition line:
// optional leading whitespace, a colon, then whitespace or end-of-line.
is_def_line :: proc(line: string) -> bool {
	trimmed := strings.trim_left(line, " \t")
	if len(trimmed) < 1 || trimmed[0] != ':' {
		return false
	}
	if len(trimmed) == 1 {
		return true
	}
	return trimmed[1] == ' ' || trimmed[1] == '\t'
}

// def_content extracts the definition text from a definition line,
// stripping the leading colon and surrounding whitespace.
def_content :: proc(line: string) -> string {
	trimmed := strings.trim_left(line, " \t")
	content := trimmed[1:]
	content = strings.trim_left(content, " \t")
	return content
}

// is_blank_line returns true for empty or whitespace-only lines.
is_blank_line :: proc(line: string) -> bool {
	return strings.trim_space(line) == ""
}

// render_deflist builds the <dl> HTML block from a list of entries.
// Each term and definition is rendered through cmark to process inline
// markdown. Result lives in context.temp_allocator.
render_deflist :: proc(entries: [dynamic]DefList_Entry) -> string {
	sb := strings.builder_make(context.temp_allocator)

	strings.write_string(&sb, "<dl>")
	for entry in entries {
		term_html := render_inline_md(entry.term)
		def_html := render_inline_md(entry.definition)
		strings.write_string(&sb, "<dt>")
		strings.write_string(&sb, term_html)
		strings.write_string(&sb, "</dt><dd>")
		strings.write_string(&sb, def_html)
		strings.write_string(&sb, "</dd>")
	}
	strings.write_string(&sb, "</dl>")

	return strings.to_string(sb)
}

// render_inline_md renders a snippet of markdown through cmark and strips
// the surrounding <p> tags. Result lives in context.temp_allocator.
render_inline_md :: proc(text: string) -> string {
	raw := cm.markdown_to_html_from_string(text, {.Unsafe})
	defer cm.free_string(raw)
	return strings.clone(strip_p_tags(raw), context.temp_allocator)
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

