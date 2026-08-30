#+test
package mustache

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// ---------------------------------------------------------------------------
// format_tag_error — golden output tests
// ---------------------------------------------------------------------------

@(test)
test_format_error_basic :: proc(t: ^testing.T) {
	src := "line 1\nline 2\n{{bad}}\nline 4\nline 5"
	out := format_tag_error("p.html", src, 14, "unknown key 'bad'", "", colorize = false)
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
	out := format_tag_error(
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
	out := format_tag_error("p.html", src, 0, "msg", "", colorize = false)
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
	out := format_tag_error("p.html", src, 0, "msg", "", colorize = false)
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
	out := format_tag_error("p.html", src, 28, "msg", "", colorize = false)
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
	out := format_tag_error("p.html", src, 2, "msg", "", colorize = false)
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
	out := format_tag_error("p.html", src, 0, "msg", "", colorize = false)
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
	out := format_tag_error("p.html", src, 32, "msg", "", colorize = false)
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

	out := format_tag_error("p.html", src, pos, "msg", "", colorize = false)
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
	out := format_tag_error("p.html", src, 0, "msg", "", colorize = false)
	// Caret line should start with "^" right after "| " (no leading spaces).
	testing.expect(t, strings.contains(out, "  | ^^^^^^^\n"), out)
}

@(test)
test_caret_at_column_N :: proc(t: ^testing.T) {
	src := "    {{bad}}"
	// pos=4 is the first '{'. Line 1, col 5.
	out := format_tag_error("p.html", src, 4, "msg", "", colorize = false)
	// 4 leading spaces, then 7 carets.
	testing.expect(t, strings.contains(out, "  |     ^^^^^^^\n"), out)
}

@(test)
test_caret_width_matches_token :: proc(t: ^testing.T) {
	src := "{{x}}"
	out := format_tag_error("p.html", src, 0, "msg", "", colorize = false)
	// {{x}} is 5 chars wide.
	testing.expect(t, strings.contains(out, "  | ^^^^^\n"), out)
}

// ---------------------------------------------------------------------------
// Context count
// ---------------------------------------------------------------------------

@(test)
test_context_before_zero :: proc(t: ^testing.T) {
	src := "l1\nl2\nl3\n{{bad}}\nl5\nl6"
	out := format_tag_error(
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
	out := format_tag_error(
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
	out := format_tag_error(
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
	out := format_tag_error("p.html", src, 3, "msg", "", colorize = false)
	// All "|" characters should appear at the same column.
	// For width=1: source line is "N | ...", so "|" at col 2.
	// Empty gutter is "  |" (width+1 spaces + "|"), so "|" at col 2.
	lines := strings.split(out, "\n", context.temp_allocator)
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
	out := format_tag_error("p.html", src, 0, "msg", "", colorize = false)
	// For width=1: arrow line is " --> ..." so ">" at col 3.
	// Pipe lines are "  |" so "|" at col 2.
	lines := strings.split(out, "\n", context.temp_allocator)

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
	out := format_tag_error("test.html", src, b.pos, b.msg, colorize = false)
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

// ---------------------------------------------------------------------------
// Data-driven diagnostic cases (from DIAGNOSTIC_TESTS.yaml)
//
// write_diagnostic_tests generates diagnostic_test_cases_test.odin from the
// enabled cases in DIAGNOSTIC_TESTS.yaml. On the first run (or when the YAML
// changes), it regenerates the file and fails. On the second run, each case
// runs as an individual test via run_diag_case.
// ---------------------------------------------------------------------------

Diag_Context :: struct {
	items:  [5]string,
	word:   string,
	params: json.Object,
	now:    string,
}

diag_ctx :: proc() -> Diag_Context {
	params_raw := `{ "author": { "name": "foo bar"}}`
	params_val, err := json.parse(params_raw, allocator = context.temp_allocator)
	assert(err == nil)
	params, ok := params_val.(json.Object)
	assert(ok)
	return Diag_Context {
		items = {"a", "b", "c", "d", "e"},
		word = "Hello, World!",
		params = params,
		now = "2026-08-10T16:21:55-04:00",
	}
}

diag_partials :: proc() -> map[string]Template {
	dirs := [?]string{#directory, "fixtures/layouts/partials"}
	partials_dir, _ := filepath.join(dirs[:], context.temp_allocator)
	partials := load_partials(partials_dir, allocator = context.temp_allocator)
	// #directory expands to an absolute, build-environment-specific path (e.g.
	// /build/... inside the nix sandbox vs a local checkout). Strip it so
	// partial diagnostics reference a stable path across environments, keeping
	// the golden expected output deterministic.
	for key, tmpl in partials {
		t := tmpl
		rel := strings.trim_prefix(t.path, #directory)
		t.path = strings.trim_left(rel, "/")
		partials[key] = t
	}
	return partials
}

diag_slug :: proc(name: string) -> string {
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	prev_underscore := false
	for r in name {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			strings.write_rune(&sb, r)
			prev_underscore = false
		} else if r >= 'A' && r <= 'Z' {
			strings.write_rune(&sb, r + 32)
			prev_underscore = false
		} else {
			if !prev_underscore && strings.builder_len(sb) > 0 {
				strings.write_rune(&sb, '_')
				prev_underscore = true
			}
		}
	}
	s := strings.to_string(sb)
	if len(s) > 0 && s[len(s) - 1] == '_' {
		s = s[:len(s) - 1]
	}
	return s
}

render_silenced :: proc(
	tmpl: Template,
	data: any,
	partials: map[string]Template = nil,
	allocator := context.allocator,
	warnings: ^[dynamic]Error = nil,
) -> (string, Error) {
	saved := context.logger
	context.logger = log.nil_logger()
	result, err := render(tmpl, data, partials, allocator, warnings)
	context.logger = saved
	return result, err
}

run_diag_case :: proc(t: ^testing.T, name: string) {
	cases := load_diag_cases("../DIAGNOSTIC_TESTS.yaml")
	ctx := diag_ctx()
	partials := diag_partials()

	for c in cases {
		if c.name != name do continue

		switch c.should {
		case "error":
			tmpl, perr := parse(c.input, "<test>", allocator = context.temp_allocator)
			if perr != nil {
				formatted := format_render_error(perr, tmpl, colorize = false)
				testing.expect_value(t, formatted, c.expected)
				return
			}

			_, rerr := render_silenced(tmpl, ctx, partials, context.temp_allocator)
			testing.expect(
				t,
				rerr != nil,
				fmt.tprintf("[%s] should error but render succeeded", c.name),
			)
			if rerr == nil do return

			formatted := format_render_error(rerr, tmpl, colorize = false)
			testing.expect_value(t, formatted, c.expected)

		case "pass":
			tmpl, perr := parse(c.input, "<test>", allocator = context.temp_allocator)
			testing.expect(
				t,
				perr == nil,
				fmt.tprintf(
					"[%s] should parse, got: %s",
					c.name,
					perr != nil ? format_render_error(perr, tmpl, colorize = false) : "",
				),
			)
			if perr != nil do return

			_, rerr := render_silenced(tmpl, ctx, partials, context.temp_allocator)
			testing.expect(
				t,
				rerr == nil,
				fmt.tprintf(
					"[%s] should not error, got: %s",
					c.name,
					rerr != nil ? format_render_error(rerr, tmpl, colorize = false) : "",
				),
			)

		case "ok":
			tmpl, perr := parse(c.input, "<test>", allocator = context.temp_allocator)
			testing.expect(
				t,
				perr == nil,
				fmt.tprintf(
					"[%s] should parse, got: %s",
					c.name,
					perr != nil ? format_render_error(perr, tmpl, colorize = false) : "",
				),
			)
			if perr != nil do return

			result, rerr := render_silenced(tmpl, ctx, partials, context.temp_allocator)
			testing.expect(
				t,
				rerr == nil,
				fmt.tprintf(
					"[%s] should not error, got: %s",
					c.name,
					rerr != nil ? format_render_error(rerr, tmpl, colorize = false) : "",
				),
			)
			if rerr != nil do return

			testing.expect_value(t, result, c.expected)

		case "warn":
			tmpl, perr := parse(c.input, "<test>", allocator = context.temp_allocator)
			testing.expect(
				t,
				perr == nil,
				fmt.tprintf(
					"[%s] should parse, got: %s",
					c.name,
					perr != nil ? format_render_error(perr, tmpl, colorize = false) : "",
				),
			)
			if perr != nil do return

			warnings := make([dynamic]Error, 0, 4, context.temp_allocator)
			_, rerr := render_silenced(tmpl, ctx, partials, context.temp_allocator, &warnings)
			testing.expect(
				t,
				rerr == nil,
				fmt.tprintf(
					"[%s] should not error, got: %s",
					c.name,
					rerr != nil ? format_render_error(rerr, tmpl, colorize = false) : "",
				),
			)
			if rerr != nil do return

			testing.expect(
				t,
				len(warnings) > 0,
				fmt.tprintf("[%s] should produce a warning", c.name),
			)
			if len(warnings) == 0 do return

			formatted := format_render_error(warnings[0], tmpl, colorize = false)
			testing.expect_value(t, formatted, c.expected)

		case:
			testing.expectf(t, false, "[%s] unknown should value: '%s'", c.name, c.should)
		}
		return
	}

	testing.expectf(t, false, "case '%s' not found in DIAGNOSTIC_TESTS.yaml", name)
}

@(test)
write_diagnostic_tests :: proc(t: ^testing.T) {
	cases := load_diag_cases("../DIAGNOSTIC_TESTS.yaml")
	testing.expect(t, len(cases) > 0, "should load diagnostic cases")

	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	strings.write_string(&sb, "#+test\n")
	strings.write_string(&sb, "package mustache\n\n")
	strings.write_string(&sb, "import \"core:testing\"\n\n")

	count := 0
	for c in cases {
		if !c.enable do continue
		if c.should == "" {
			testing.expectf(t, false, "[%s] has enable: true but no should value", c.name)
			continue
		}
		count += 1
		slug := diag_slug(c.name)
		strings.write_string(&sb, "@(test)\n")
		strings.write_string(&sb, "test_diag_")
		strings.write_string(&sb, slug)
		strings.write_string(&sb, " :: proc(t: ^testing.T) {\n")
		strings.write_string(&sb, "\trun_diag_case(t, \"")
		strings.write_string(&sb, c.name)
		strings.write_string(&sb, "\")\n}\n\n")
	}

	testing.expect(t, count > 0, "at least one case should be enabled")

	generated := strings.to_string(sb)

	dirs := [?]string{#directory, "diagnostic_test_cases_test.odin"}
	gen_path, _ := filepath.join(dirs[:], context.temp_allocator)

	existing_data, _ := os.read_entire_file_from_path(gen_path, context.temp_allocator)
	existing := string(existing_data)

	if existing == generated do return

	werr := os.write_entire_file(gen_path, transmute([]byte)generated)
	if werr != nil {
		testing.expectf(t, false, "failed to write %s: %v", gen_path, werr)
		return
	}
	testing.expectf(
		t,
		false,
		"diagnostic_test_cases_test.odin regenerated (%d cases), re-run tests to see results",
		count,
	)
}

