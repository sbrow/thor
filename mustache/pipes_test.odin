#+test
package mustache

import "core:fmt"
import "core:testing"

Pipe_Post :: struct {
	title: string,
	year:  string,
}

Pipe_Data :: struct {
	posts: []Pipe_Post,
}

make_data :: proc(posts: ..Pipe_Post) -> Pipe_Data {
	d: Pipe_Data
	d.posts = posts
	return d
}

@(test)
test_pipe_group_by_basic :: proc(t: ^testing.T) {
	data := make_data(
		{title = "A", year = "2024"},
		{title = "B", year = "2024"},
		{title = "C", year = "2023"},
	)
	tpl, _ := parse("{{#posts | group_by year}}{{key}}:{{#items}}{{title}},{{/items}};{{/posts}}")
	defer delete_template(&tpl)
	result, _ := render(tpl, data)
	defer delete(result)
	testing.expect_value(t, result, "2024:A,B,;2023:C,;")
}

@(test)
test_pipe_group_by_doesnt_sort :: proc(t: ^testing.T) {
	data := make_data(
		{title = "old", year = "2020"},
		{title = "new", year = "2024"},
		{title = "mid", year = "2022"},
	)
	tpl, _ := parse("{{#posts | group_by year}}{{key}} {{/posts}}")
	defer delete_template(&tpl)
	result, _ := render(tpl, data)
	defer delete(result)
	testing.expect_value(t, result, "2020 2024 2022 ")
}

@(test)
test_pipe_group_by_empty_list_skips :: proc(t: ^testing.T) {
	data := Pipe_Data {
		posts = nil,
	}
	tpl, _ := parse("[{{#posts | group_by year}}{{key}}{{/posts}}]")
	defer delete_template(&tpl)
	result, _ := render(tpl, data)
	defer delete(result)
	testing.expect_value(t, result, "[]")
}

@(test)
test_pipe_group_by_missing_field_fails :: proc(t: ^testing.T) {
	data := make_data({title = "A", year = "2024"})
	tpl, _ := parse("{{#posts | group_by missing}}x{{/posts}}")
	defer delete_template(&tpl)
	_, err := render(tpl, data)
	testing.expect(t, err != nil, "missing field should error")
	b := body(err)
	testing.expect(t, b.kind == .Data, "error should be Data kind")
	testing.expect(t, len(b.msg) > 0, "error should have non-empty msg")
}

@(test)
test_pipe_group_by_requires_grouped_field :: proc(t: ^testing.T) {
	data := make_data({title = "A", year = ""})
	tpl, _ := parse("{{#posts | group_by year}}x{{/posts}}")
	defer delete_template(&tpl)
	_, err := render(tpl, data)
	testing.expect(t, err != nil, "empty field value should error")
}

@(test)
test_group_by_requires_arg :: proc(t: ^testing.T) {
	data := make_data({title = "A", year = "2024"})
	tpl, _ := parse("{{#posts | group_by}}x{{/posts}}")
	defer delete_template(&tpl)
	_, err := render(tpl, data)
	testing.expect(t, err != nil, "group_by with no args should error")
}

@(test)
test_pipe_group_by_non_list_returns_error :: proc(t: ^testing.T) {
	Scalar_Data :: struct {
		name: string,
	}
	data := Scalar_Data {
		name = "hello",
	}
	tpl, _ := parse("{{#name | group_by x}}y{{/name}}")
	defer delete_template(&tpl)
	_, err := render(tpl, data)
	testing.expect(t, err != nil, "group_by on a scalar should error")
}

@(test)
test_pipe_accepts_8_filters :: proc(t: ^testing.T) {
	src := "{{#posts | group_by year | group_by year | group_by year | group_by year | group_by year | group_by year | group_by year | group_by year}}x{{/posts}}"
	tpl, err := parse(src)
	testing.expect(t, err == nil, "8 filters should parse OK")
	if err == nil {
		defer delete_template(&tpl)
	} else {
		fmt.printfln("parse error: %v", err)
	}
}

@(test)
test_pipe_rejects_nine_filters :: proc(t: ^testing.T) {
	src := "{{#posts | group_by y | group_by y | group_by y | group_by y | group_by y | group_by y | group_by y | group_by y | group_by y}}x{{/posts}}"
	_, err := parse(src)
	testing.expect(t, err != nil, "9 filters should fail to parse")
}

@(test)
test_pipe_forbidden_in_close_tag :: proc(t: ^testing.T) {
	src := "{{#posts | group_by year}}x{{/posts | group_by year}}"
	_, err := parse(src)
	testing.expect(t, err != nil, "pipe in close tag should fail to parse")
}

@(test)
test_pipe_empty_middle_filter_required :: proc(t: ^testing.T) {
	src := "{{#posts | | group_by year}}x{{/posts}}"
	_, err := parse(src)
	testing.expect(t, err != nil, "empty pipe filter should fail to parse")
}

@(test)
test_pipe_filter_required :: proc(t: ^testing.T) {
	src := "{{#posts |}}x{{/posts}}"
	_, err := parse(src)
	testing.expect(t, err != nil, "trailing pipe with no filter should fail")
}

@(test)
test_pipe_data_required :: proc(t: ^testing.T) {
	src := "{{#| group_by year}}x{{/}}"
	_, err := parse(src)
	testing.expect(t, err != nil, "missing key should fail to parse")
}

@(test)
test_extra_whitespace_allowed :: proc(t: ^testing.T) {
	data := make_data({title = "A", year = "2024"}, {title = "B", year = "2023"})
	tpl, _ := parse("{{#posts|group_by   year}}{{key}};{{/posts}}")
	defer delete_template(&tpl)
	result, _ := render(tpl, data)
	defer delete(result)
	testing.expect_value(t, result, "2024;2023;")
}


@(test)
test_pipe_no_pipe_still_works :: proc(t: ^testing.T) {
	data := make_data({title = "A", year = "2024"}, {title = "B", year = "2023"})
	tpl, _ := parse("{{#posts}}{{title}};{{/posts}}")
	defer delete_template(&tpl)
	result, _ := render(tpl, data)
	defer delete(result)
	testing.expect_value(t, result, "A;B;")
}

@(test)
test_pipe_inverted_section_empty :: proc(t: ^testing.T) {
	data := Pipe_Data {
		posts = nil,
	}
	tpl, _ := parse("{{^posts | group_by year}}none{{/posts}}")
	defer delete_template(&tpl)
	result, _ := render(tpl, data)
	defer delete(result)
	testing.expect_value(t, result, "none")
}

@(test)
test_pipe_single_group_works :: proc(t: ^testing.T) {
	data := make_data({title = "A", year = "2024"}, {title = "B", year = "2024"})
	tpl, _ := parse("{{#posts | group_by year}}{{key}}({{#items}}{{title}}{{/items}}){{/posts}}")
	defer delete_template(&tpl)
	result, _ := render(tpl, data)
	defer delete(result)
	testing.expect_value(t, result, "2024(AB)")
}

@(test)
test_delete_template_doesnt_leak :: proc(t: ^testing.T) {
	tmpl, err := parse("{{#posts | group_by year}}x{{/posts}}")
	testing.expect(t, err == nil)
	defer delete_template(&tmpl)
}

// ---------------------------------------------------------------------------
// Interpolation pipes ({{x | op}})
// ---------------------------------------------------------------------------

@(test)
test_interp_pipe_basic :: proc(t: ^testing.T) {
	Scalar_Data :: struct {
		name:        string,
		date_format: string,
	}
	data := Scalar_Data {
		name = "2026-03-15T08:49:54-04:00",
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse("[{{name | format}}]", "<test>", allocator = context.temp_allocator)
	result, _ := render(tpl, data, {}, context.temp_allocator)
	testing.expect_value(t, result, "[15 Mar 2026]")
}

@(test)
test_interp_pipe_unescaped :: proc(t: ^testing.T) {
	Scalar_Data :: struct {
		name:        string,
		date_format: string,
	}
	data := Scalar_Data {
		name = "2025-12-25T00:00:00Z",
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse("[{{&name | format}}]", "<test>", allocator = context.temp_allocator)
	result, _ := render(tpl, data, {}, context.temp_allocator)
	testing.expect_value(t, result, "[25 Dec 2025]")
}

@(test)
test_interp_pipe_dot_current :: proc(t: ^testing.T) {
	List_Data :: struct {
		items:       [3]string,
		date_format: string,
	}
	data := List_Data {
		items = {"2026-01-06T00:00:00Z", "2026-06-15T00:00:00Z", "2026-10-15T00:00:00Z"},
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse("{{#items}}[{{. | format}}]{{/items}}", "<test>", allocator = context.temp_allocator)
	result, _ := render(tpl, data, {}, context.temp_allocator)
	testing.expect_value(t, result, "[6 Jan 2026][15 Jun 2026][15 Oct 2026]")
}

// ---------------------------------------------------------------------------
// format filter
// ---------------------------------------------------------------------------

Format_Data :: struct {
	date:        string,
	date_format: string,
}

@(test)
test_format_typical_iso :: proc(t: ^testing.T) {
	data := Format_Data {
		date = "2026-03-15T08:49:54-04:00",
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse("{{date | format}}", "<test>", allocator = context.temp_allocator)
	result, _ := render(tpl, data, {}, context.temp_allocator)
	testing.expect_value(t, result, "15 Mar 2026")
}

@(test)
test_format_short_date_only :: proc(t: ^testing.T) {
	data := Format_Data {
		date = "2026-06-06",
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse("{{date | format}}", "<test>", allocator = context.temp_allocator)
	result, _ := render(tpl, data, {}, context.temp_allocator)
	testing.expect_value(t, result, "6 Jun 2026")
}

@(test)
test_format_empty_input_errors :: proc(t: ^testing.T) {
	data := Format_Data {
		date = "",
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse("[{{date | format}}]", "<test>", allocator = context.temp_allocator)
	defer delete_template(&tpl)
	_, err := render(tpl, data, {}, context.temp_allocator)
	testing.expect(t, err != nil, "empty date should error")
}

@(test)
test_format_non_date_string_errors :: proc(t: ^testing.T) {
	data := Format_Data {
		date = "abc",
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse("[{{date | format}}]", "<test>", allocator = context.temp_allocator)
	defer delete_template(&tpl)
	_, err := render(tpl, data, {}, context.temp_allocator)
	testing.expect(t, err != nil, "non-date string should error")
}

@(test)
test_format_non_string_value_errors :: proc(t: ^testing.T) {
	Int_Data :: struct {
		count: int,
	}
	data := Int_Data {
		count = 42,
	}
	tpl, _ := parse("{{count | format}}", "<test>", allocator = context.temp_allocator)
	defer delete_template(&tpl)
	_, err := render(tpl, data, {}, context.temp_allocator)
	testing.expect(t, err != nil, "non-string value should error")
}

@(test)
test_format_invalid_month_errors :: proc(t: ^testing.T) {
	data := Format_Data {
		date = "2023-13-15",
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse("{{date | format}}", "<test>", allocator = context.temp_allocator)
	defer delete_template(&tpl)
	_, err := render(tpl, data, {}, context.temp_allocator)
	testing.expect(t, err != nil, "invalid month should error")
}

@(test)
test_format_inside_section_renders :: proc(t: ^testing.T) {
	// Mirrors the datetime.html partial pattern: section pushes raw string,
	// partial uses {{.}} for ISO attr and {{. | format}} for display.
	data := Format_Data {
		date = "2025-12-25T00:00:00Z",
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse(
		"{{#date}}<time datetime=\"{{.}}\">{{. | format}}</time>{{/date}}",
		"<test>",
		allocator = context.temp_allocator,
	)
	result, _ := render(tpl, data, {}, context.temp_allocator)
	testing.expect_value(t, result, "<time datetime=\"2025-12-25T00:00:00Z\">25 Dec 2025</time>")
}

@(test)
test_format_inside_section_skips_when_empty :: proc(t: ^testing.T) {
	data := Format_Data {
		date = "",
		date_format = "2 Jan 2006",
	}
	tpl, _ := parse("[{{#date}}<time>{{. | format}}</time>{{/date}}]", "<test>", allocator = context.temp_allocator)
	result, _ := render(tpl, data, {}, context.temp_allocator)
	testing.expect_value(t, result, "[]")
}

@(test)
test_format_context_date_format_weekday :: proc(t: ^testing.T) {
	data := Format_Data {
		date        = "2026-01-01T00:00:00Z",
		date_format = "Monday, January 2, 2006",
	}
	tpl, _ := parse("{{date | format}}", "<test>", allocator = context.temp_allocator)
	result, _ := render(tpl, data, {}, context.temp_allocator)
	testing.expect_value(t, result, "Thursday, January 1, 2026")
}

@(test)
test_format_context_date_format_time_of_day :: proc(t: ^testing.T) {
	data := Format_Data {
		date        = "2026-01-01T15:30:00Z",
		date_format = "3:04 PM",
	}
	tpl, _ := parse("{{date | format}}", "<test>", allocator = context.temp_allocator)
	result, _ := render(tpl, data, {}, context.temp_allocator)
	testing.expect_value(t, result, "3:30 PM")
}

@(test)
test_format_handles_all_iso8601_variants :: proc(t: ^testing.T) {
	cases := [5]struct {
		input, expected: string,
	} {
		{"2023-10-15T13:18:50-07:00", "15 Oct 2023"},
		{"2023-10-15T13:18:50-0700", "15 Oct 2023"},
		{"2023-10-15T13:18:50Z", "15 Oct 2023"},
		{"2023-10-15T13:18:50", "15 Oct 2023"},
		{"2023-10-15", "15 Oct 2023"},
	}
	for &c in cases {
		data := Format_Data {
			date = c.input,
			date_format = "2 Jan 2006",
		}
		tpl, _ := parse("{{date | format}}", "<test>", allocator = context.temp_allocator)
		result, _ := render(tpl, data, {}, context.temp_allocator)
		testing.expect_value(t, result, c.expected)
	}
}

