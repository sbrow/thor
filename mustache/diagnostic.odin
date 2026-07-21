package mustache

import "core:fmt"
import "core:os"
import "core:strings"
import "core:terminal/ansi"
import "core:unicode/utf8"

// line_col returns the 1-indexed line and column for a byte offset in source.
// Newlines ('\n') separate lines; '\r' is treated as part of '\r\n'. Column is
// counted in bytes from the start of the line.
line_col :: proc(source: string, pos_in: int) -> (line: int, col: int) {
	pos := pos_in
	if pos < 0 {
		return 1, 1
	}
	if pos > len(source) {
		pos = len(source)
	}
	line = 1
	col = 1
	for i := 0; i < pos; i += 1 {
		if source[i] == '\n' {
			line += 1
			col = 1
		} else {
			col += 1
		}
	}
	return
}

// line_text returns the Nth (1-indexed) line of source, without the trailing
// newline. Returns "" if line is out of range.
line_text :: proc(source: string, line: int) -> string {
	if line < 1 {
		return ""
	}
	current := 1
	start := 0
	for i := 0; i < len(source); i += 1 {
		if current == line {
			end := i
			for end < len(source) && source[end] != '\n' {
				end += 1
			}
			return source[start:end]
		}
		if source[i] == '\n' {
			current += 1
			start = i + 1
		}
	}
	if current == line {
		return source[start:]
	}
	return ""
}

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

// should_colorize returns true if stderr is a TTY and color output is wanted.
should_colorize :: proc() -> bool {
	return os.is_tty(os.stderr)
}

// count_lines returns the number of '\n'-separated lines in source.
// A trailing newline does not add an extra line.
count_lines :: proc(source: string) -> int {
	if len(source) == 0 {
		return 1
	}
	n := 1
	for c in source {
		if c == '\n' {
			n += 1
		}
	}
	// Drop phantom last line if source ends with '\n'.
	if len(source) > 0 && source[len(source) - 1] == '\n' {
		n -= 1
	}
	return n
}

// digit_count returns the number of decimal digits in n (min 1).
digit_count :: proc(n: int) -> int {
	if n <= 0 {
		return 1
	}
	c := 0
	x := n
	for x > 0 {
		c += 1
		x /= 10
	}
	return c
}

// display_width returns the number of terminal cells `s` occupies.
// For ASCII this is byte length; for UTF-8 we count runes (combining
// marks and wide CJK chars are still approximate).
display_width :: proc(s: string) -> int {
	return utf8.rune_count_in_string(s)
}

// format_error produces a rust-style multi-line diagnostic string.
//
//   <msg>
//    --> <path>:<line>:<col>
//     |
//  N | <source line N-2>
//  N | <source line N-1>
//  N | <source line N — the error line>
//     |     ^^^^^^^^^^^ <hint>
//  N | <source line N+1>
//  N | <source line N+2>
//     |
//
// `context_before`/`context_after` lines of context are shown around the
// error line. Line numbers are right-aligned to the width of the largest
// line number shown.
format_error :: proc(
	path: string,
	source: string,
	pos: int,
	msg: string,
	hint: string = "",
	context_before: int = 2,
	context_after: int = 2,
	colorize: bool = false,
) -> string {
	line, col := line_col(source, pos)
	total_lines := count_lines(source)

	start_line := line - context_before
	if start_line < 1 {
		start_line = 1
	}
	end_line := line + context_after
	if end_line > total_lines {
		end_line = total_lines
	}

	// Width of the line-number column (right-align).
	width := digit_count(end_line)
	if width < 1 {
		width = 1
	}

	sb := strings.builder_make(context.temp_allocator)
	defer strings.builder_destroy(&sb)

	color := colorize
	red, faint, reset := "", "", ""
	if color {
		red = ansi.CSI + ansi.FG_RED + ansi.SGR
		faint = ansi.CSI + ansi.FAINT + ansi.SGR
		reset = ansi.CSI + ansi.RESET + ansi.SGR
	}

	// Header line: message.
	strings.write_string(&sb, msg)
	strings.write_byte(&sb, '\n')

	// Location line: "  --> path:line:col" (width spaces + arrow).
	strings.write_string(&sb, faint)
	for _ in 0 ..< width {
		strings.write_byte(&sb, ' ')
	}
	strings.write_string(&sb, "--> ")
	strings.write_string(&sb, reset)
	strings.write_string(&sb, fmt.tprintf("%s:%d:%d\n", path, line, col))

	// Top gutter line.
	write_gutter(&sb, width, faint, reset)

	// Caret extent for the error line.
	_, token_start, token_end := context_extent(source, pos)
	line_start, _, _ := context_extent(source, pos)
	caret_start_col := token_start - line_start + 1
	caret_end_col := token_end - line_start + 1
	if caret_end_col <= caret_start_col {
		caret_end_col = caret_start_col + 1
	}

	// Context lines.
	for n in start_line ..= end_line {
		// Line number (right-aligned, faint).
		num_str := fmt.tprintf("%d", n)
		strings.write_string(&sb, faint)
		for _ in 0 ..< width - len(num_str) {
			strings.write_byte(&sb, ' ')
		}
		strings.write_string(&sb, num_str)
		strings.write_string(&sb, " | ")
		strings.write_string(&sb, reset)

		strings.write_string(&sb, line_text(source, n))
		strings.write_byte(&sb, '\n')

		// After the error line, emit the caret row.
		if n == line {
			strings.write_string(&sb, faint)
			for _ in 0 ..< width + 1 {
				strings.write_byte(&sb, ' ')
			}
			strings.write_string(&sb, "| ")
			strings.write_string(&sb, reset)

			for _ in 1 ..< caret_start_col {
				strings.write_byte(&sb, ' ')
			}
			if color {
				strings.write_string(&sb, red)
			}
			for _ in 0 ..< caret_end_col - caret_start_col {
				strings.write_byte(&sb, '^')
			}
			if color {
				strings.write_string(&sb, reset)
			}
			if hint != "" {
				strings.write_byte(&sb, ' ')
				if color {
					strings.write_string(&sb, faint)
				}
				strings.write_string(&sb, hint)
				if color {
					strings.write_string(&sb, reset)
				}
			}
			strings.write_byte(&sb, '\n')
		}
	}

	// Trailing gutter line for visual closure.
	write_gutter(&sb, width, faint, reset)

	return strings.to_string(sb)
}

// write_gutter emits a faint pipe-only gutter line: `<width+1 spaces> |`.
write_gutter :: proc(sb: ^strings.Builder, width: int, faint: string, reset: string) {
	strings.write_string(sb, faint)
	for _ in 0 ..< width + 1 {
		strings.write_byte(sb, ' ')
	}
	strings.write_string(sb, "|")
	strings.write_string(sb, reset)
	strings.write_byte(sb, '\n')
}

// format_render_error dispatches on Render_Error variant and produces a
// diagnostic for it. Returns "" for nil errors.
format_render_error :: proc(err: Render_Error, tmpl: Template, colorize: bool = false) -> string {
	if err == nil {
		return ""
	}
	switch e in err {
	case Syntax_Error:
		path := tmpl.path
		if path == "" {
			path = "<input>"
		}
		return format_error(path, tmpl.source, e.pos, e.msg, colorize = colorize)
	case Data_Error:
		path := tmpl.path
		if path == "" {
			path = "<input>"
		}
		return format_error(path, tmpl.source, e.pos, e.msg, colorize = colorize)
	}
	return ""
}

