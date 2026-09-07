package markdown

import cm "vendor:commonmark"

import "core:strings"

// convert_deflists scans markdown text for definition list patterns and
// converts them to <dl><dt><dd> HTML blocks before cmark processing.
//
// A definition line starts with fewer than four columns of leading whitespace
// followed by a colon and a space (or end-of-line). The term is the nearest
// preceding non-blank line (immediately or within one blank line). Consecutive
// term+definition pairs are grouped into a single <dl> block, and consecutive
// definition lines under one term become multiple <dd> elements.
//
// The scanner walks the body one line at a time using byte offsets: it never
// splits the input, allocates nothing per line, and copies non-deflist text
// through verbatim. Matching is disabled inside fenced code blocks. Terms and
// definitions are rendered through cmark individually so that inline markdown
// (code, links, emphasis) is processed.
// Line_Kind classifies a line for convert_deflists's group-finding scan. Other
// covers fenced-code delimiters and their contents, where definition syntax is
// inert.
Line_Kind :: enum {
	None,
	Blank,
	Term,
	Def,
	Other,
}

convert_deflists :: proc(body: string, allocator := context.allocator) -> string {
	// Fast path: a body with no definition line at all cannot contain a
	// definition list, so return it untouched — skipping the builder allocation
	// and the classifying scan below. This is the common case (most pages have
	// no definition lists), and the guard scan is leaner than the full loop.
	if !has_def_line(body) {
		return body
	}

	sb := strings.builder_make(context.temp_allocator)

	// emitted_up_to is the byte offset up to which `body` has been copied into
	// `sb`. It stays at 0 until the first deflist is emitted; if it is still 0
	// at the end, nothing matched and we can return the body unchanged.
	emitted_up_to := 0

	in_fence := false
	fence_marker: u8 = 0

	// The scan is definition-driven: it walks line by line, remembering the two
	// previous lines' kinds and offsets, and only does group-finding work when it
	// reaches a (rare) definition line — whose term is the immediately preceding
	// line, or the one before a single blank line. This avoids a per-line forward
	// lookahead: each line is classified once, with no rescanning.
	prev1_kind, prev2_kind := Line_Kind.None, Line_Kind.None
	prev1_pos, prev2_pos := 0, 0

	pos := 0
	for {
		line, next, ok := line_at(body, pos)
		if !ok {
			break
		}

		// Classify the line. Definition-list syntax is inert inside fenced code
		// blocks, so fence delimiters and their contents are classified Other.
		kind: Line_Kind
		if in_fence {
			if is_fence_line(line, fence_marker) {
				in_fence = false
			}
			kind = .Other
		} else if marker, opened := fence_open(line); opened {
			in_fence = true
			fence_marker = marker
			kind = .Other
		} else if is_def_line(line) {
			kind = .Def
		} else if is_blank_line(line) {
			kind = .Blank
		} else {
			kind = .Term
		}

		// A definition-list group begins at the term preceding this def line
		// (immediately, or across a single blank line). Flush pending passthrough
		// text verbatim, then render the whole group directly into the builder.
		if kind == .Def {
			term_pos := -1
			if prev1_kind == .Term {
				term_pos = prev1_pos
			} else if prev1_kind == .Blank && prev2_kind == .Term {
				term_pos = prev2_pos
			}
			if term_pos >= 0 {
				strings.write_string(&sb, body[emitted_up_to:term_pos])
				group_end := write_deflist_group(&sb, body, term_pos)
				// write_deflist_group emits a raw <dl> HTML block with no
				// trailing newline, so the blank line the author left after the
				// list is consumed as the </dl> line's terminator rather than a
				// separating blank line. CommonMark (type-6 HTML block) then
				// swallows the following block — e.g. a fenced code example —
				// as raw, unescaped HTML, leaking its markup (a template's
				// <h1>) into the document. Re-emit a newline so </dl> stands on
				// its own line and the author's blank line still separates the
				// block. Only when a blank line actually follows: fused
				// non-blank fall-through content is left as-is.
				if line, _, ok := line_at(body, group_end); ok && is_blank_line(line) {
					strings.write_byte(&sb, '\n')
				}
				emitted_up_to = group_end
				pos = group_end
				prev1_kind, prev2_kind = .None, .None
				in_fence = false
				continue
			}
		}

		prev2_kind, prev2_pos = prev1_kind, prev1_pos
		prev1_kind, prev1_pos = kind, pos
		pos = next
	}

	if emitted_up_to == 0 {
		// No definition list anywhere; the body passes through unchanged.
		return body
	}
	strings.write_string(&sb, body[emitted_up_to:])
	return strings.clone(strings.to_string(sb), allocator)
}

// line_at returns the line beginning at byte offset `pos` (excluding its
// trailing newline) along with the offset of the following line. `pos` must be
// 0 or one past a '\n'. ok is false once `pos` reaches the end of `body`.
line_at :: proc(body: string, pos: int) -> (line: string, next: int, ok: bool) {
	if pos >= len(body) {
		return "", pos, false
	}
	nl := strings.index_byte(body[pos:], '\n')
	if nl < 0 {
		return body[pos:], len(body), true
	}
	return body[pos:pos + nl], pos + nl + 1, true
}

// has_def_line reports whether any line in `body` is a definition line (see
// is_def_line). It is a cheap guard for convert_deflists: a body with no
// definition line cannot contain a definition list. There are no false
// negatives (every definition list requires a definition line); a false
// positive — e.g. a colon line that only appears inside a code fence — simply
// falls through to the full scan, which then finds no match and returns `body`.
has_def_line :: proc(body: string) -> bool {
	pos := 0
	for {
		line, next := line_at(body, pos) or_break
		if is_def_line(line) {
			return true
		}
		pos = next
	}
	return false
}

// write_deflist_group renders the definition-list group beginning at `start`
// directly into `sb`, wrapped in <dl>...</dl>, and returns the byte offset one
// past the group (the start of the first line not consumed). The caller must
// have confirmed via term_has_def that a group starts at `start`, so the group
// always contains at least one term+definition pair. A trailing blank line that
// separates the group from following content is left unconsumed.
write_deflist_group :: proc(sb: ^strings.Builder, body: string, start: int) -> (end: int) {
	strings.write_string(sb, "<dl>")

	pos := start
	for {
		term_line, term_next, term_ok := line_at(body, pos)
		if !term_ok || is_blank_line(term_line) || is_def_line(term_line) {
			break
		}

		// The definition follows immediately or across a single blank line.
		def_pos := term_next
		def_line, def_next, def_ok := line_at(body, def_pos)
		if def_ok && is_blank_line(def_line) {
			def_pos = def_next
			def_line, def_next, def_ok = line_at(body, def_pos)
		}
		if !def_ok || !is_def_line(def_line) {
			break
		}

		// Emit the term with its first definition, then any consecutive
		// definition lines as additional <dd>s under the same term.
		strings.write_string(sb, "<dt>")
		strings.write_string(sb, render_inline_md(strings.trim_space(term_line)))
		strings.write_string(sb, "</dt><dd>")
		strings.write_string(sb, render_inline_md(def_content(def_line)))
		strings.write_string(sb, "</dd>")
		pos = def_next
		for {
			cont, cont_next, cont_ok := line_at(body, pos)
			if !cont_ok || !is_def_line(cont) {
				break
			}
			strings.write_string(sb, "<dd>")
			strings.write_string(sb, render_inline_md(def_content(cont)))
			strings.write_string(sb, "</dd>")
			pos = cont_next
		}

		// Continue the group if another term+definition pair follows,
		// optionally separated by one blank line. Otherwise stop here without
		// consuming a trailing blank line.
		blank_line, after_blank, blank_ok := line_at(body, pos)
		if blank_ok && is_blank_line(blank_line) {
			if term_has_def(body, after_blank) {
				pos = after_blank
				continue
			}
			break
		}
		// No blank line: loop and let the top re-test this line as a term.
	}

	strings.write_string(sb, "</dl>")
	return pos
}

// term_has_def reports whether the line at `pos` is a term that is immediately
// (or across one blank line) followed by a definition line.
term_has_def :: proc(body: string, pos: int) -> bool {
	line, next, ok := line_at(body, pos)
	if !ok || is_blank_line(line) || is_def_line(line) {
		return false
	}
	def_pos := next
	def_line, def_next, def_ok := line_at(body, def_pos)
	if def_ok && is_blank_line(def_line) {
		def_pos = def_next
		def_line, def_next, def_ok = line_at(body, def_pos)
	}
	return def_ok && is_def_line(def_line)
}

// fence_open reports whether `line` opens a fenced code block and, if so, which
// marker character it uses. Leading spaces are ignored.
fence_open :: proc(line: string) -> (marker: u8, ok: bool) {
	trimmed := strings.trim_left(line, " ")
	if strings.has_prefix(trimmed, "```") {
		return '`', true
	}
	if strings.has_prefix(trimmed, "~~~") {
		return '~', true
	}
	return 0, false
}

// is_fence_line reports whether `line` is a fence using the given marker
// character (used to detect the closing fence of an open block).
is_fence_line :: proc(line: string, marker: u8) -> bool {
	trimmed := strings.trim_left(line, " ")
	if marker == '~' {
		return strings.has_prefix(trimmed, "~~~")
	}
	return strings.has_prefix(trimmed, "```")
}

// is_def_line returns true if the line is a definition line: fewer than four
// columns of leading whitespace, a colon, then whitespace or end-of-line. Four
// or more columns of indentation is a code block, not a definition.
is_def_line :: proc(line: string) -> bool {
	indent := 0
	n := 0
	for n < len(line) && (line[n] == ' ' || line[n] == '\t') {
		indent += line[n] == '\t' ? 4 : 1
		n += 1
	}
	if indent >= 4 {
		return false
	}
	rest := line[n:]
	if len(rest) < 1 || rest[0] != ':' {
		return false
	}
	if len(rest) == 1 {
		return true
	}
	return rest[1] == ' ' || rest[1] == '\t'
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

