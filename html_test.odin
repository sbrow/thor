#+test
package main

import "core:testing"

// --- generate_summary ---

@(test)
test_summary_short :: proc(t: ^testing.T) {
	result := generate_summary("<p>Hello world</p>")
	testing.expect_value(t, result, "<p>Hello world</p>")
}

@(test)
test_summary_word_limit :: proc(t: ^testing.T) {
	result := generate_summary("<p>one two three four five</p>", max_words = 3)
	testing.expect_value(t, result, "<p>one two three")
}

@(test)
test_summary_empty :: proc(t: ^testing.T) {
	result := generate_summary("")
	testing.expect_value(t, result, "")
}

@(test)
test_summary_no_words :: proc(t: ^testing.T) {
	result := generate_summary("<p></p>")
	testing.expect_value(t, result, "<p></p>")
}

@(test)
test_summary_tags_not_counted :: proc(t: ^testing.T) {
	html := `<pre><code><span class="hl-keyword">if</span> x</code></pre>`
	result := generate_summary(html, max_words = 1)
	testing.expect_value(t, result, `<pre><code><span class="hl-keyword">if`)
}

// --- generate_description ---

@(test)
test_description_simple :: proc(t: ^testing.T) {
	result := generate_description("<p>Hello world</p>")
	testing.expect_value(t, result, "Hello world")
}

@(test)
test_description_entities :: proc(t: ^testing.T) {
	result := generate_description("<p>Cats &amp; dogs &lt;3</p>")
	testing.expect_value(t, result, "Cats & dogs <3")
}

@(test)
test_description_nested_tags :: proc(t: ^testing.T) {
	result := generate_description("<p><strong>Bold</strong> text</p>")
	testing.expect_value(t, result, "Bold text")
}

@(test)
test_description_block_boundary :: proc(t: ^testing.T) {
	result := generate_description("<p>First</p><p>Second</p>")
	testing.expect_value(t, result, "First Second")
}

@(test)
test_description_whitespace_collapse :: proc(t: ^testing.T) {
	result := generate_description("<p>  Multiple   spaces  </p>")
	testing.expect_value(t, result, "Multiple spaces")
}

@(test)
test_description_empty :: proc(t: ^testing.T) {
	result := generate_description("")
	testing.expect_value(t, result, "")
}

@(test)
test_description_plain_text :: proc(t: ^testing.T) {
	result := generate_description("Just plain text")
	testing.expect_value(t, result, "Just plain text")
}

@(test)
test_description_highlighted_code :: proc(t: ^testing.T) {
	result := generate_description(`<pre><code><span class="hl-keyword">if</span> x</code></pre>`)
	testing.expect_value(t, result, "if x")
}

@(test)
test_description_list_items :: proc(t: ^testing.T) {
	result := generate_description("<ul><li>One</li><li>Two</li></ul>")
	testing.expect_value(t, result, "One Two")
}

@(test)
test_description_headings :: proc(t: ^testing.T) {
	result := generate_description("<h1>Title</h1><p>Body</p>")
	testing.expect_value(t, result, "Title Body")
}

@(test)
test_description_blockquote :: proc(t: ^testing.T) {
	result := generate_description("<blockquote>Quote</blockquote>")
	testing.expect_value(t, result, "Quote")
}
