#+test
package markdown

import "core:strings"
import "core:testing"

@(test)
test_single_entry :: proc(t: ^testing.T) {
	input := "term\n\n: definition"
	result := convert_deflists(input, context.temp_allocator)
	expected := "<dl><dt>term</dt><dd>definition</dd></dl>"
	testing.expect_value(t, result, expected)
}

@(test)
test_single_entry_no_blank :: proc(t: ^testing.T) {
	input := "term\n: definition"
	result := convert_deflists(input, context.temp_allocator)
	expected := "<dl><dt>term</dt><dd>definition</dd></dl>"
	testing.expect_value(t, result, expected)
}

@(test)
test_indented_variant :: proc(t: ^testing.T) {
	input := " term\n : definition"
	result := convert_deflists(input, context.temp_allocator)
	expected := "<dl><dt>term</dt><dd>definition</dd></dl>"
	testing.expect_value(t, result, expected)
}

@(test)
test_multiple_entries :: proc(t: ^testing.T) {
	input := "t1\n\n: d1\n\nt2\n\n: d2"
	result := convert_deflists(input, context.temp_allocator)
	expected := "<dl><dt>t1</dt><dd>d1</dd><dt>t2</dt><dd>d2</dd></dl>"
	testing.expect_value(t, result, expected)
}

@(test)
test_mixed_indented_and_non_indented :: proc(t: ^testing.T) {
	input := "t1\n\n: d1\n\n t2\n : d2\n\nt3\n\n: d3"
	result := convert_deflists(input, context.temp_allocator)
	expected := "<dl><dt>t1</dt><dd>d1</dd><dt>t2</dt><dd>d2</dd><dt>t3</dt><dd>d3</dd></dl>"
	testing.expect_value(t, result, expected)
}

@(test)
test_inline_markdown_in_term :: proc(t: ^testing.T) {
	input := "`code`\n\n: def"
	result := convert_deflists(input, context.temp_allocator)
	expected := "<dl><dt><code>code</code></dt><dd>def</dd></dl>"
	testing.expect_value(t, result, expected)
}

@(test)
test_inline_markdown_in_definition :: proc(t: ^testing.T) {
	input := "term\n\n: see [Content](#content) here"
	result := convert_deflists(input, context.temp_allocator)
	testing.expect(t, strings.contains(result, `<a href="#content">Content</a>`))
	testing.expect(t, strings.contains(result, "<dd>see "))
	testing.expect(t, strings.contains(result, "</dd>"))
}

@(test)
test_regular_text_passes_through :: proc(t: ^testing.T) {
	input := "This is: not a deflist"
	result := convert_deflists(input, context.temp_allocator)
	testing.expect_value(t, result, input)
}

@(test)
test_colon_inside_paragraph_no_false_positive :: proc(t: ^testing.T) {
	input := "First paragraph.\n\nSecond paragraph."
	result := convert_deflists(input, context.temp_allocator)
	testing.expect_value(t, result, input)
}

@(test)
test_deflist_between_paragraphs :: proc(t: ^testing.T) {
	input := "Before.\n\nterm\n\n: def\n\nAfter."
	result := convert_deflists(input, context.temp_allocator)
	testing.expect(t, strings.has_prefix(result, "Before."))
	testing.expect(t, strings.contains(result, "<dl><dt>term</dt><dd>def</dd></dl>"))
	testing.expect(t, strings.has_suffix(result, "After."))
}

@(test)
test_empty_body :: proc(t: ^testing.T) {
	result := convert_deflists("", context.temp_allocator)
	testing.expect_value(t, result, "")
}

@(test)
test_docs_md_pattern :: proc(t: ^testing.T) {
	input := "content\n\n: `content` holds your pages.\n\n assets\n : `assets` contains files."
	result := convert_deflists(input, context.temp_allocator)
	testing.expect(t, strings.contains(result, "<dl>"))
	testing.expect(t, strings.contains(result, "<dt>content</dt>"))
	testing.expect(t, strings.contains(result, "<dt>assets</dt>"))
	testing.expect(t, strings.contains(result, "<code>content</code>"))
	testing.expect(t, strings.contains(result, "<code>assets</code>"))
	testing.expect(t, strings.contains(result, "</dl>"))
}

