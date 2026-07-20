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

	is_data_err := false
	#partial switch e in err {
	case Data_Error:
		is_data_err = len(e.msg) > 0
	}
	testing.expect(t, is_data_err, "error should be Data_Error")
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

