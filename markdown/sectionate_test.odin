#+test
package markdown

import "core:testing"

@(test)
test_wrap_sections_works :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		wrap_sections("<p>intro</p><h2>Title</h2><p>body</p>"),
		"<section><p>intro</p></section><section><h2>Title</h2><p>body</p></section>",
	)

	testing.expect_value(
		t,
		wrap_sections("<p>a</p><h2>A</h2><p>b</p><h2>B</h2><p>c</p>"),
		"<section><p>a</p></section><section><h2>A</h2><p>b</p></section><section><h2>B</h2><p>c</p></section>",
	)

	testing.expect_value(
		t,
		wrap_sections("<h2>Title</h2><p>body</p>"),
		"<section><h2>Title</h2><p>body</p></section>",
	)

	testing.expect_value(
		t,
		wrap_sections("<p>intro</p><h2>Title</h2>"),
		"<section><p>intro</p></section><section><h2>Title</h2></section>",
	)
}

@(test)
test_wrap_sections_doesnt_split_content :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		wrap_sections("<p>just text</p>"),
		"<section><p>just text</p></section>",
	)

	testing.expect_value(t, wrap_sections(""), "")

	testing.expect_value(
		t,
		wrap_sections("<h1>Big</h1><h3>Small</h3>"),
		"<section><h1>Big</h1><h3>Small</h3></section>",
	)
}

