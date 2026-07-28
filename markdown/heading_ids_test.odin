#+test
package markdown

import "core:testing"

@(test)
test_heading_simple :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h2>Hello World</h2>")
	testing.expect_value(t, result, `<h2 id="hello-world">Hello World</h2>`)
}

@(test)
test_heading_dedup :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h2>Intro</h2><p>text</p><h2>Intro</h2>")
	testing.expect_value(t, result, `<h2 id="intro">Intro</h2><p>text</p><h2 id="intro-1">Intro</h2>`)
}

@(test)
test_heading_nested_html :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h3>With <code>code</code></h3>")
	testing.expect_value(t, result, `<h3 id="with-code">With <code>code</code></h3>`)
}

@(test)
test_heading_entities :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h2>Cats &amp; Dogs</h2>")
	testing.expect_value(t, result, `<h2 id="cats-dogs">Cats &amp; Dogs</h2>`)
}

@(test)
test_heading_punctuation :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h2>Hello, World!</h2>")
	testing.expect_value(t, result, `<h2 id="hello-world">Hello, World!</h2>`)
}

@(test)
test_heading_all_levels :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h1>A</h1><h2>B</h2><h3>C</h3><h4>D</h4><h5>E</h5><h6>F</h6>")
	testing.expect_value(t, result,
		`<h1 id="a">A</h1>` +
		`<h2 id="b">B</h2>` +
		`<h3 id="c">C</h3>` +
		`<h4 id="d">D</h4>` +
		`<h5 id="e">E</h5>` +
		`<h6 id="f">F</h6>`,
	)
}

@(test)
test_heading_preserves_text :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h2>It is <em>bold</em></h2>")
	testing.expect_value(t, result, `<h2 id="it-is-bold">It is <em>bold</em></h2>`)
}

@(test)
test_heading_non_heading_tags :: proc(t: ^testing.T) {
	input := "<header>Nav</header><h2>Title</h2><hr>"
	result := inject_heading_ids(input)
	testing.expect_value(t, result, `<header>Nav</header><h2 id="title">Title</h2><hr>`)
}

@(test)
test_heading_existing_attrs_skipped :: proc(t: ^testing.T) {
	input := `<h2 class="foo">Title</h2>`
	result := inject_heading_ids(input)
	testing.expect_value(t, result, input)
}

@(test)
test_heading_empty :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h2></h2><h3></h3>")
	testing.expect_value(t, result, `<h2 id="section-1"></h2><h3 id="section-2"></h3>`)
}

@(test)
test_heading_with_surrounding_content :: proc(t: ^testing.T) {
	input := "<p>Before</p><h2>Title</h2><p>After</p>"
	result := inject_heading_ids(input)
	testing.expect_value(t, result, `<p>Before</p><h2 id="title">Title</h2><p>After</p>`)
}

@(test)
test_heading_numbers :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h2>Chapter 12</h2>")
	testing.expect_value(t, result, `<h2 id="chapter-12">Chapter 12</h2>`)
}

@(test)
test_heading_triple_dedup :: proc(t: ^testing.T) {
	result := inject_heading_ids("<h2>Foo</h2><h2>Foo</h2><h2>Foo</h2>")
	testing.expect_value(t, result,
		`<h2 id="foo">Foo</h2>` +
		`<h2 id="foo-1">Foo</h2>` +
		`<h2 id="foo-2">Foo</h2>`,
	)
}
