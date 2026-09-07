#+test
package markdown

import "core:strings"
import "core:testing"

@(test)
test_toc_sequential_nesting :: proc(t: ^testing.T) {
	html := `<h1 id="a">A</h1><h2 id="b">B</h2><h1 id="c">C</h1>`
	result := generate_toc(html, context.temp_allocator)
	testing.expect(t, strings.contains(result, `<a href="#a">A</a>`))
	testing.expect(t, strings.contains(result, `<a href="#b">B</a>`))
	testing.expect(t, strings.contains(result, `<a href="#c">C</a>`))
	// A well-formed list never places a <ul> directly inside a <ul>.
	testing.expect(t, !strings.contains(result, "<ul>\n<ul>"))
}

// Regression: a heading level that jumps by more than one (h1 -> h3) must not
// emit stacked, parentless <ul> tags. Each skipped level is wrapped in an <li>
// so the list stays valid.
@(test)
test_toc_level_jump_stays_valid :: proc(t: ^testing.T) {
	html := `<h1 id="a">A</h1><h3 id="b">B</h3>`
	result := generate_toc(html, context.temp_allocator)
	testing.expect(t, !strings.contains(result, "<ul>\n<ul>"))
	// The intermediate level is hosted by an <li>.
	testing.expect(t, strings.contains(result, "<li>\n<ul>"))
	testing.expect(t, strings.contains(result, `<a href="#b">B</a>`))
}

@(test)
test_toc_empty_when_no_headings :: proc(t: ^testing.T) {
	result := generate_toc("<p>no headings here</p>", context.temp_allocator)
	testing.expect_value(t, result, "")
}
