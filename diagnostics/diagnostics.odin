package diagnostics

import "core:fmt"
import "core:os"
import "core:strings"
import "core:terminal/ansi"
import "core:unicode/utf8"

// suggest_correction returns the closest match from `available` to `missing`
// using Levenshtein distance, or "" if no good match exists. The threshold
// scales with the length of the missing key.
suggest_correction :: proc(available: []string, missing: string) -> string {
	if len(available) == 0 || len(missing) == 0 {
		return ""
	}
	threshold := max(2, len(missing) / 3)

	best: string
	best_dist := threshold + 1
	for candidate in available {
		if abs(len(candidate) - len(missing)) > threshold {
			continue
		}
		d := strings.levenshtein_distance(missing, candidate)
		if d <= threshold && d < best_dist {
			best = candidate
			best_dist = d
		}
	}
	return best
}

// line_col returns the 1-indexed line and column for a byte offset in source.
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

// should_colorize returns true if stderr is a TTY and color output is wanted.
should_colorize :: proc() -> bool {
	return os.is_tty(os.stderr)
}

// count_lines returns the number of '\n'-separated lines in source.
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
display_width :: proc(s: string) -> int {
	return utf8.rune_count_in_string(s)
}

// line_start_at returns the byte offset of the start of the line containing pos.
line_start_at :: proc(source: string, pos_in: int) -> int {
	pos := pos_in
	if pos < 0 {
		return 0
	}
	if pos >= len(source) {
		pos = len(source) - 1
	}
	for pos > 0 && source[pos - 1] != '\n' {
		pos -= 1
	}
	return pos
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
// `caret_start`/`caret_end` control the byte range of the caret underline.
// If not provided (or negative), defaults to a single-rune underline at `pos`.
format_error :: proc(
	path: string,
	source: string,
	pos: int,
	msg: string,
	hint: string = "",
	context_before: int = 2,
	context_after: int = 2,
	colorize: bool = false,
	caret_start: int = -1,
	caret_end: int = -1,
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

	width := digit_count(end_line)
	if width < 1 {
		width = 1
	}

	cs := caret_start >= 0 ? caret_start : pos
	ce := caret_end > cs ? caret_end : cs + 1

	ls := line_start_at(source, pos)
	caret_start_col := cs - ls + 1
	caret_end_col := ce - ls + 1

	sb := strings.builder_make(context.temp_allocator)
	defer strings.builder_destroy(&sb)

	red, faint, reset := "", "", ""
	if colorize {
		red = ansi.CSI + ansi.FG_RED + ansi.SGR
		faint = ansi.CSI + ansi.FAINT + ansi.SGR
		reset = ansi.CSI + ansi.RESET + ansi.SGR
	}

	// Header
	strings.write_string(&sb, msg)
	strings.write_byte(&sb, '\n')

	// Location line
	strings.write_string(&sb, faint)
	for _ in 0 ..< width {
		strings.write_byte(&sb, ' ')
	}
	strings.write_string(&sb, "--> ")
	strings.write_string(&sb, reset)
	fmt.sbprintf(&sb, "%s:%d:%d\n", path, line, col)

	// Top gutter
	write_gutter(&sb, width, faint, reset)

	// Context lines
	for n in start_line ..= end_line {
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

		// Caret row after error line
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
			if colorize {
				strings.write_string(&sb, red)
			}
			for _ in 0 ..< caret_end_col - caret_start_col {
				strings.write_byte(&sb, '^')
			}
			if colorize {
				strings.write_string(&sb, reset)
			}
			if hint != "" {
				strings.write_byte(&sb, ' ')
				if colorize {
					strings.write_string(&sb, faint)
				}
				strings.write_string(&sb, hint)
				if colorize {
					strings.write_string(&sb, reset)
				}
			}
			strings.write_byte(&sb, '\n')
		}
	}

	// Trailing gutter
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
