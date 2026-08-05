package mustache

import diags "../diagnostics"

// context_extent returns the byte offset of the start of the line containing
// pos, plus the byte offsets of the start and end of the mustache tag at pos.
// Used to underline the offending tag. If pos is not inside a tag, the
// returned [token_start, token_end) is a single rune at pos.
context_extent :: proc(
	source: string,
	pos_in: int,
) -> (
	line_start: int,
	token_start: int,
	token_end: int,
) {
	pos := pos_in
	if pos < 0 {
		return 0, 0, 0
	}
	if pos >= len(source) {
		pos = len(source) - 1
	}
	line_start = pos
	for line_start > 0 && source[line_start - 1] != '\n' {
		line_start -= 1
	}

	// Scan forward from line_start for `{{ ... }}` tags. If pos falls inside
	// any tag's byte range, return that tag's extent.
	i := line_start
	for i + 1 < len(source) {
		if source[i] == '{' && source[i + 1] == '{' {
			tag_start := i
			// Find closing }}
			j := i + 2
			depth := 1
			for j + 1 < len(source) && depth > 0 {
				if source[j] == '{' && source[j + 1] == '{' {
					depth += 1
					j += 2
				} else if source[j] == '}' && source[j + 1] == '}' {
					depth -= 1
					j += 2
				} else {
					j += 1
				}
			}
			tag_end := j
			if pos >= tag_start && pos < tag_end {
				return line_start, tag_start, tag_end
			}
			i = tag_end
		} else {
			i += 1
		}
	}

	// Not inside a tag — underline a single rune at pos.
	return line_start, pos, pos + 1
}

// format_tag_error is a mustache-aware wrapper around diags.format_error.
// It uses context_extent to compute the caret underline for `{{ }}` tags,
// falling back to a single-rune underline when pos is not inside a tag.
// When `span > 0`, the caret extends from pos to pos + span.
format_tag_error :: proc(
	path: string,
	source: string,
	pos: int,
	msg: string,
	hint: string = "",
	context_before: int = 2,
	context_after: int = 2,
	colorize: bool = false,
	span: int = 0,
) -> string {
	caret_start := pos
	caret_end := pos + 1
	if span > 0 {
		caret_end = pos + span
	} else {
		_, ts, te := context_extent(source, pos)
		caret_start = ts
		caret_end = te
	}
	return diags.format_error(
		path, source, pos, msg, hint,
		context_before, context_after,
		colorize,
		caret_start, caret_end,
	)
}

// format_render_error produces a diagnostic for an Error value using the
// template's path and source for context. Returns "" for nil errors.
format_render_error :: proc(err: Error, tmpl: Template, colorize: bool = false) -> string {
	if err == nil {
		return ""
	}
	b := body(err)
	source := b.source != "" ? b.source : tmpl.source
	path := b.path != "" ? b.path : tmpl.path
	if path == "" {
		path = "<input>"
	}

	caret_start := b.pos
	caret_end := b.pos + 1
	if b.span > 0 {
		caret_end = b.pos + b.span
	} else {
		_, ts, te := context_extent(source, b.pos)
		caret_start = ts
		caret_end = te
	}

	return diags.format_error(
		path, source, b.pos, b.msg,
		hint = b.hint,
		colorize = colorize,
		caret_start = caret_start,
		caret_end = caret_end,
	)
}
