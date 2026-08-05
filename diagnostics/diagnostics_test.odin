#+test
package diagnostics

import "core:fmt"
import "core:testing"

@(test)
test_suggest_correction_exact :: proc(t: ^testing.T) {
	available := []string{"title", "page.title", "body"}
	testing.expect_value(t, suggest_correction(available, "page_titel"), "page.title")
}

@(test)
test_suggest_correction_close :: proc(t: ^testing.T) {
	available := []string{"title", "body", "now"}
	testing.expect_value(t, suggest_correction(available, "titel"), "title")
}

@(test)
test_suggest_correction_no_match :: proc(t: ^testing.T) {
	available := []string{"completely_different", "unrelated"}
	testing.expect_value(t, suggest_correction(available, "page_titel"), "")
}

@(test)
test_suggest_correction_empty :: proc(t: ^testing.T) {
	testing.expect_value(t, suggest_correction([]string{}, "anything"), "")
	testing.expect_value(t, suggest_correction([]string{"a"}, ""), "")
}

// ---------------------------------------------------------------------------
// line_col / line_text / count_lines / digit_count — primitive helpers
// ---------------------------------------------------------------------------

@(test)
test_line_col_basic :: proc(t: ^testing.T) {
	src := "abc\ndef\nghi"
	cases := [?]struct {
		pos:  int,
		line: int,
		col:  int,
	}{{0, 1, 1}, {2, 1, 3}, {3, 1, 4}, {4, 2, 1}, {6, 2, 3}, {7, 2, 4}, {8, 3, 1}}
	for c in cases {
		l, col := line_col(src, c.pos)
		testing.expect(t, l == c.line, fmt.tprintf("pos %d: line %d, want %d", c.pos, l, c.line))
		testing.expect(t, col == c.col, fmt.tprintf("pos %d: col %d, want %d", c.pos, col, c.col))
	}
}

@(test)
test_line_col_empty :: proc(t: ^testing.T) {
	l, col := line_col("", 0)
	testing.expect_value(t, l, 1)
	testing.expect_value(t, col, 1)
}

@(test)
test_line_col_negative :: proc(t: ^testing.T) {
	l, col := line_col("abc", -1)
	testing.expect_value(t, l, 1)
	testing.expect_value(t, col, 1)
}

@(test)
test_line_col_past_end :: proc(t: ^testing.T) {
	l, col := line_col("abc", 100)
	testing.expect_value(t, l, 1)
	testing.expect_value(t, col, 4)
}

@(test)
test_line_text_first :: proc(t: ^testing.T) {
	src := "first\nsecond\nthird"
	testing.expect_value(t, line_text(src, 1), "first")
	testing.expect_value(t, line_text(src, 2), "second")
	testing.expect_value(t, line_text(src, 3), "third")
}

@(test)
test_line_text_trailing_newline :: proc(t: ^testing.T) {
	src := "first\nsecond\n"
	testing.expect_value(t, line_text(src, 1), "first")
	testing.expect_value(t, line_text(src, 2), "second")
	testing.expect_value(t, line_text(src, 3), "")
}

@(test)
test_line_text_out_of_range :: proc(t: ^testing.T) {
	testing.expect_value(t, line_text("abc", 5), "")
	testing.expect_value(t, line_text("abc", 0), "")
}

@(test)
test_count_lines :: proc(t: ^testing.T) {
	testing.expect_value(t, count_lines(""), 1)
	testing.expect_value(t, count_lines("abc"), 1)
	testing.expect_value(t, count_lines("a\nb"), 2)
	testing.expect_value(t, count_lines("a\nb\n"), 2)
	testing.expect_value(t, count_lines("a\nb\nc"), 3)
}

@(test)
test_digit_count :: proc(t: ^testing.T) {
	testing.expect_value(t, digit_count(0), 1)
	testing.expect_value(t, digit_count(1), 1)
	testing.expect_value(t, digit_count(9), 1)
	testing.expect_value(t, digit_count(10), 2)
	testing.expect_value(t, digit_count(99), 2)
	testing.expect_value(t, digit_count(100), 3)
	testing.expect_value(t, digit_count(-5), 1)
}
