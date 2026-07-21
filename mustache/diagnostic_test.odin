#+test
package mustache

import "core:fmt"
import "core:strings"
import "core:testing"

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

// ---------------------------------------------------------------------------
// format_error — golden output tests
// ---------------------------------------------------------------------------

@(test)
test_format_error_basic :: proc(t: ^testing.T) {
	src := "line 1\nline 2\n{{bad}}\nline 4\nline 5"
	out := format_error("p.html", src, 14, "unknown key 'bad'", "", colorize = false)
	expected := `unknown key 'bad'
 --> p.html:3:1
  |
1 | line 1
2 | line 2
3 | {{bad}}
  | ^^^^^^^
4 | line 4
5 | line 5
  |
`
	testing.expect_value(t, out, expected)
}

@(test)
test_format_error_with_hint :: proc(t: ^testing.T) {
	src := "line 1\nline 2\n{{titel}}\nline 4\nline 5"
	out := format_error(
		"post.html",
		src,
		14,
		"unknown key 'titel'",
		"did you mean 'title'?",
		colorize = false,
	)
	expected := `unknown key 'titel'
 --> post.html:3:1
  |
1 | line 1
2 | line 2
3 | {{titel}}
  | ^^^^^^^^^ did you mean 'title'?
4 | line 4
5 | line 5
  |
`
	testing.expect_value(t, out, expected)
}

@(test)
test_format_error_no_hint_omits_trailing_space :: proc(t: ^testing.T) {
	src := "{{bad}}"
	out := format_error("p.html", src, 0, "msg", "", colorize = false)
	// Caret line ends immediately after the carets — no trailing space.
	testing.expect(t, strings.contains(out, "^^^^^^^\n"), out)
	testing.expect(t, !strings.contains(out, "^^^^^^^ \n"), out)
}

// ---------------------------------------------------------------------------
// Edge cases — context window clamping
// ---------------------------------------------------------------------------

@(test)
test_format_error_first_line_only_after_context :: proc(t: ^testing.T) {
	src := "{{bad}}\nline 2\nline 3\nline 4\nline 5"
	out := format_error("p.html", src, 0, "msg", "", colorize = false)
	expected := `msg
 --> p.html:1:1
  |
1 | {{bad}}
  | ^^^^^^^
2 | line 2
3 | line 3
  |
`
	testing.expect_value(t, out, expected)
}

@(test)
test_format_error_last_line_only_before_context :: proc(t: ^testing.T) {
	src := "line 1\nline 2\nline 3\nline 4\n{{bad}}"
	out := format_error("p.html", src, 28, "msg", "", colorize = false)
	expected := `msg
 --> p.html:5:1
  |
3 | line 3
4 | line 4
5 | {{bad}}
  | ^^^^^^^
  |
`
	testing.expect_value(t, out, expected)
}

@(test)
test_format_error_short_source_clamped :: proc(t: ^testing.T) {
	src := "x\n{{bad}}\ny"
	out := format_error("p.html", src, 2, "msg", "", colorize = false)
	expected := `msg
 --> p.html:2:1
  |
1 | x
2 | {{bad}}
  | ^^^^^^^
3 | y
  |
`
	testing.expect_value(t, out, expected)
}

@(test)
test_format_error_single_line_source :: proc(t: ^testing.T) {
	src := "{{bad}}"
	out := format_error("p.html", src, 0, "msg", "", colorize = false)
	expected := `msg
 --> p.html:1:1
  |
1 | {{bad}}
  | ^^^^^^^
  |
`
	testing.expect_value(t, out, expected)
}

@(test)
test_format_error_two_digit_line_numbers :: proc(t: ^testing.T) {
	// 12-line source; error on line 9. end_line=11 → width=2.
	src := "l01\nl02\nl03\nl04\nl05\nl06\nl07\nl08\n{{bad}}\nl10\nl11\nl12"
	// Position of `{{bad}}`: 8 lines of "l0N\n" = 8*4 = 32 bytes.
	out := format_error("p.html", src, 32, "msg", "", colorize = false)
	testing.expect(t, strings.contains(out, "  --> p.html:9:1\n"), out)
	testing.expect(t, strings.contains(out, "   |\n"), out)
	testing.expect(t, strings.contains(out, " 7 | l07\n"), out)
	testing.expect(t, strings.contains(out, " 9 | {{bad}}\n"), out)
	testing.expect(t, strings.contains(out, "11 | l11\n"), out)
}

@(test)
test_format_error_three_digit_line_numbers :: proc(t: ^testing.T) {
	// 102-line source; error on line 100. Width=3 because end_line=102 has 3 digits.
	parts: [dynamic]string
	defer delete(parts)
	for i in 1 ..= 99 {
		append(&parts, fmt.tprintf("l%03d", i))
	}
	append(&parts, "{{bad}}")
	append(&parts, "l101")
	append(&parts, "l102")
	src := strings.join(parts[:], "\n", context.temp_allocator)

	// Find byte position of "{{bad}}": after 99 lines.
	pos := 0
	for i in 1 ..= 99 {
		pos += len(parts[i - 1]) + 1
	}

	out := format_error("p.html", src, pos, "msg", "", colorize = false)
	testing.expect(t, strings.contains(out, "   --> p.html:100:1\n"), out)
	testing.expect(t, strings.contains(out, "    |\n"), out)
	testing.expect(t, strings.contains(out, " 98 | l098\n"), out)
	testing.expect(t, strings.contains(out, "100 | {{bad}}\n"), out)
	testing.expect(t, strings.contains(out, "102 | l102\n"), out)
}

// ---------------------------------------------------------------------------
// Caret position
// ---------------------------------------------------------------------------

@(test)
test_caret_at_column_1 :: proc(t: ^testing.T) {
	src := "{{bad}} at start"
	out := format_error("p.html", src, 0, "msg", "", colorize = false)
	// Caret line should start with "^" right after "| " (no leading spaces).
	testing.expect(t, strings.contains(out, "  | ^^^^^^^\n"), out)
}

@(test)
test_caret_at_column_N :: proc(t: ^testing.T) {
	src := "    {{bad}}"
	// pos=4 is the first '{'. Line 1, col 5.
	out := format_error("p.html", src, 4, "msg", "", colorize = false)
	// 4 leading spaces, then 7 carets.
	testing.expect(t, strings.contains(out, "  |     ^^^^^^^\n"), out)
}

@(test)
test_caret_width_matches_token :: proc(t: ^testing.T) {
	src := "{{x}}"
	out := format_error("p.html", src, 0, "msg", "", colorize = false)
	// {{x}} is 5 chars wide.
	testing.expect(t, strings.contains(out, "  | ^^^^^\n"), out)
}

// ---------------------------------------------------------------------------
// Context count
// ---------------------------------------------------------------------------

@(test)
test_context_before_zero :: proc(t: ^testing.T) {
	src := "l1\nl2\nl3\n{{bad}}\nl5\nl6"
	out := format_error(
		"p.html",
		src,
		9,
		"msg",
		"",
		context_before = 0,
		context_after = 1,
		colorize = false,
	)
	expected := `msg
 --> p.html:4:1
  |
4 | {{bad}}
  | ^^^^^^^
5 | l5
  |
`
	testing.expect_value(t, out, expected)
}

@(test)
test_context_after_zero :: proc(t: ^testing.T) {
	src := "l1\nl2\nl3\n{{bad}}\nl5\nl6"
	out := format_error(
		"p.html",
		src,
		9,
		"msg",
		"",
		context_before = 1,
		context_after = 0,
		colorize = false,
	)
	expected := `msg
 --> p.html:4:1
  |
3 | l3
4 | {{bad}}
  | ^^^^^^^
  |
`
	testing.expect_value(t, out, expected)
}

@(test)
test_context_both_zero :: proc(t: ^testing.T) {
	src := "l1\nl2\nl3\n{{bad}}\nl5\nl6"
	out := format_error(
		"p.html",
		src,
		9,
		"msg",
		"",
		context_before = 0,
		context_after = 0,
		colorize = false,
	)
	expected := `msg
 --> p.html:4:1
  |
4 | {{bad}}
  | ^^^^^^^
  |
`
	testing.expect_value(t, out, expected)
}

// ---------------------------------------------------------------------------
// Gutter/alignment
// ---------------------------------------------------------------------------

@(test)
test_gutter_pipes_align_with_source_pipe :: proc(t: ^testing.T) {
	src := "l1\n{{bad}}\nl3"
	out := format_error("p.html", src, 3, "msg", "", colorize = false)
	// All "|" characters should appear at the same column.
	// For width=1: source line is "N | ...", so "|" at col 2.
	// Empty gutter is "  |" (width+1 spaces + "|"), so "|" at col 2.
	lines := strings.split(out, "\n", context.temp_allocator)
	defer delete(lines)
	pipe_col := -1
	for line in lines {
		idx := strings.index(line, "|")
		if idx < 0 {
			continue
		}
		if pipe_col < 0 {
			pipe_col = idx
		} else {
			testing.expect_value(t, idx, pipe_col)
		}
	}
}

@(test)
test_arrow_points_at_pipe :: proc(t: ^testing.T) {
	src := "{{bad}}"
	out := format_error("p.html", src, 0, "msg", "", colorize = false)
	// For width=1: arrow line is " --> ..." so ">" at col 3.
	// Pipe lines are "  |" so "|" at col 2.
	lines := strings.split(out, "\n", context.temp_allocator)
	defer delete(lines)

	pipe_col := -1
	for line in lines {
		idx := strings.index(line, "|")
		if idx >= 0 {
			pipe_col = idx
			break
		}
	}
	testing.expect(t, pipe_col >= 0, "expected pipe in output")

	// Find the arrow line specifically and verify its ">" column.
	arrow_col := -1
	for line in lines {
		idx := strings.index(line, "-->")
		if idx >= 0 {
			arrow_col = idx + 2 // ">" is the last char of "-->"
			break
		}
	}
	testing.expect(t, arrow_col >= 0, "expected --> in output")
	testing.expect_value(t, arrow_col, pipe_col + 1)
}

// ---------------------------------------------------------------------------
// format_render_error — dispatch
// ---------------------------------------------------------------------------

@(test)
test_format_render_error_dispatch :: proc(t: ^testing.T) {
	src := "{{#unclosed}}\ncontent"
	tmpl, parse_err := parse(src, "test.html")
	testing.expect(t, parse_err != nil, "should fail to parse unclosed section")
	if parse_err == nil {
		return
	}

	b := body(parse_err)
	out := format_error("test.html", src, b.pos, b.msg, colorize = false)
	testing.expect(t, strings.contains(out, "unclosed section"), out)
	testing.expect(t, strings.contains(out, "test.html:"), out)
}

@(test)
test_diagnostic_for_pipe_error :: proc(t: ^testing.T) {
	src := "{{#name | group_by year}}x{{/name}}"
	tmpl, perr := parse(src, "test.html")
	testing.expect(t, perr == nil, "should parse")
	if perr != nil {
		return
	}
	defer delete_template(&tmpl)

	Data :: struct {
		name: string,
	}
	_, rerr := render(tmpl, Data{name = "hello"})
	testing.expect(t, rerr != nil, "should fail to render")
	if rerr == nil {
		return
	}

	out := format_render_error(rerr, tmpl, colorize = false)
	testing.expect(t, strings.contains(out, "group_by expects a list"), out)
	testing.expect(t, strings.contains(out, "test.html:"), out)
}

// ---------------------------------------------------------------------------
// Parser error messages preserve double braces in tag syntax
// ---------------------------------------------------------------------------

@(test)
test_parse_error_expected_got_keeps_double_braces :: proc(t: ^testing.T) {
	src := "{{#content}}body{{/cotent}}"
	_, err := parse(src, "test.html")
	testing.expect(t, err != nil, "should fail to parse")
	if err == nil {
		return
	}
	b := body(err)
	testing.expect(
		t,
		strings.contains(b.msg, "{{/content}}"),
		fmt.tprintf("msg should contain literal {{/content}}, got %q", b.msg),
	)
	testing.expect(
		t,
		strings.contains(b.msg, "{{/cotent}}"),
		fmt.tprintf("msg should contain literal {{/cotent}}, got %q", b.msg),
	)
}

@(test)
test_parse_error_unclosed_section_keeps_double_braces :: proc(t: ^testing.T) {
	src := "{{#content}}body"
	_, err := parse(src, "test.html")
	testing.expect(t, err != nil, "should fail to parse")
	if err == nil {
		return
	}
	b := body(err)
	testing.expect(
		t,
		strings.contains(b.msg, "{{#content}}"),
		fmt.tprintf("msg should contain literal {{#content}}, got %q", b.msg),
	)
}

@(test)
test_parse_error_unexpected_close_keeps_double_braces :: proc(t: ^testing.T) {
	src := "text{{/content}}"
	_, err := parse(src, "test.html")
	testing.expect(t, err != nil, "should fail to parse")
	if err == nil {
		return
	}
	b := body(err)
	testing.expect(
		t,
		strings.contains(b.msg, "{{/content}}"),
		fmt.tprintf("msg should contain literal {{/content}}, got %q", b.msg),
	)
}

@(test)
test_parse_error_pipe_in_close_tag_keeps_double_braces :: proc(t: ^testing.T) {
	src := "{{#posts | group_by year}}x{{/posts | group_by year}}"
	_, err := parse(src, "test.html")
	testing.expect(t, err != nil, "should fail to parse")
	if err == nil {
		return
	}
	b := body(err)
	testing.expect(
		t,
		strings.contains(b.msg, "{{/"),
		fmt.tprintf("msg should contain literal '{{/', got %q", b.msg),
	)
}

@(test)
test_parse_error_pipe_parse_in_section_keeps_double_braces :: proc(t: ^testing.T) {
	src := "{{#posts |}}x{{/posts}}"
	_, err := parse(src, "test.html")
	testing.expect(t, err != nil, "should fail to parse")
	if err == nil {
		return
	}
	b := body(err)
	testing.expect(
		t,
		strings.contains(b.msg, "{{#"),
		fmt.tprintf("msg should contain literal '{{#', got %q", b.msg),
	)
}

@(test)
test_parse_error_pipe_parse_in_inverted_keeps_double_braces :: proc(t: ^testing.T) {
	src := "{{^posts |}}x{{/posts}}"
	_, err := parse(src, "test.html")
	testing.expect(t, err != nil, "should fail to parse")
	if err == nil {
		return
	}
	b := body(err)
	testing.expect(
		t,
		strings.contains(b.msg, "{{^"),
		fmt.tprintf("msg should contain literal '{{^', got %q", b.msg),
	)
}

