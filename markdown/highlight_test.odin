#+test
package markdown

import ts "../treesitter"

import "core:mem"
import "core:strings"
import "core:testing"

// highlight_block returns the input string unchanged (borrowed) when it can't
// highlight — no grammar, no query, or zero captures — and a freshly-allocated
// string when it does. Free only the latter; identity (raw_data) tells them
// apart regardless of content.
@(private = "file")
free_highlight :: proc(out, code: string) {
	if raw_data(out) != raw_data(code) {
		delete(out)
	}
}

// A builtin grammar (css) highlights into hl- spans, preserving the source text.
@(test)
test_highlight_block_css :: proc(t: ^testing.T) {
	code := "a{color:red}"
	out := highlight_block(code, "css", "test")
	defer free_highlight(out, code)

	testing.expect(t, strings.contains(out, "<span class=\"hl-"), "css should be highlighted")
	testing.expect(t, strings.contains(out, "</span>"))
	testing.expect(t, strings.contains(out, "color"))
	testing.expect(t, strings.contains(out, "red"))
}

// The other builtin grammar (html) highlights, and the source's own '<'/'>' are
// HTML-escaped in the output (so they can't be confused with the wrapping spans).
@(test)
test_highlight_block_html_escapes_source :: proc(t: ^testing.T) {
	code := "<p>hi</p>"
	out := highlight_block(code, "html", "test")
	defer free_highlight(out, code)

	testing.expect(t, strings.contains(out, "<span class=\"hl-"), "html should be highlighted")
	testing.expect(t, strings.contains(out, "hi"))
	// The literal angle brackets of the source are escaped in the output.
	testing.expect(t, strings.contains(out, "&lt;"))
	testing.expect(t, strings.contains(out, "&gt;"))
}

// A language with no available grammar returns the input verbatim (best-effort:
// highlighting is optional). The returned string must be the same buffer, so
// free_highlight leaves it alone.
@(test)
test_highlight_block_unknown_lang_passthrough :: proc(t: ^testing.T) {
	code := "fn main() {}"
	out := highlight_block(code, "no-such-language", "test")
	defer free_highlight(out, code)

	testing.expect_value(t, out, code)
	testing.expect(t, raw_data(out) == raw_data(code), "passthrough must return the input buffer")
}

// End-to-end: highlight_code finds a fenced code block in rendered HTML and
// rewrites its body with highlight spans while preserving the <pre><code> shell.
// Run under a scratch arena (as production does) so the intermediate allocations
// highlight_code doesn't individually free are reclaimed in one shot.
@(test)
test_highlight_code_wraps_css_block :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	html := `<pre><code class="language-css">a{color:red}</code></pre>`
	out := highlight_code(html, "test")

	testing.expect(t, strings.contains(out, `<pre><code class="language-css">`))
	testing.expect(t, strings.contains(out, "</code></pre>"))
	testing.expect(
		t,
		strings.contains(out, "<span class=\"hl-"),
		"block body should be highlighted",
	)
}
