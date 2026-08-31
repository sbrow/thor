#+test
package main

import ts "treesitter"

import "core:strings"
import "core:testing"

// The treesitter registry is thread-safe and self-initializing (grammar() lazily
// binds it to the heap), and parsers are caller-owned. Each test opens its own
// parser(s) via ts.open_parser, passes them to minify_*, and frees the returned
// string — so the multi-threaded test runner needs no shared state or locking.

@(private = "file")
open_parsers :: proc(t: ^testing.T) -> (html_parser, css_parser: ts.Parser) {
	hg, hok := ts.grammar("html")
	cg, cok := ts.grammar("css")
	testing.expect(t, hok, "html grammar should load")
	testing.expect(t, cok, "css grammar should load")
	return ts.open_parser(hg), ts.open_parser(cg)
}

@(private = "file")
expect_css :: proc(t: ^testing.T, parser: ts.Parser, input, want: string) {
	got, ok := minify_css(parser, input)
	testing.expect(t, ok)
	defer delete(got)
	testing.expect_value(t, got, want)
}

// --- minify_html: inline <style> bodies get CSS-minified ---

@(test)
test_minify_html_inline_style :: proc(t: ^testing.T) {
	hp, cp := open_parsers(t)
	defer ts.parser_delete(hp)
	defer ts.parser_delete(cp)

	input := `<html><head><style>
body {
  color:  red;
}
</style></head><body><p>hi</p></body></html>`
	result, ok := minify_html(hp, cp, input)
	testing.expect(t, ok)
	defer delete(result)

	// The CSS body is collapsed by minify_css (delimiters lose surrounding
	// whitespace)...
	testing.expect(t, strings.contains(result, "body{color:red;}"))
	// ...while the <style> tags themselves survive.
	testing.expect(t, strings.contains(result, "<style>"))
	testing.expect(t, strings.contains(result, "</style>"))
}

@(test)
test_minify_html_empty_style :: proc(t: ^testing.T) {
	hp, cp := open_parsers(t)
	defer ts.parser_delete(hp)
	defer ts.parser_delete(cp)

	// An empty <style></style> has no raw_text child; must not crash.
	input := `<html><head><style></style></head><body></body></html>`
	result, ok := minify_html(hp, cp, input)
	testing.expect(t, ok)
	defer delete(result)
	testing.expect(t, strings.contains(result, "<style></style>"))
}

// --- minify_css: whitespace around stripped comments / leading edge ---

@(test)
test_minify_css_leading_and_comment :: proc(t: ^testing.T) {
	cg, cok := ts.grammar("css")
	testing.expect(t, cok, "css grammar should load")
	cp := ts.open_parser(cg)
	defer ts.parser_delete(cp)

	// Leading whitespace and a comment between two whitespace runs must not
	// leave a leading space or a doubled space.
	expect_css(t, cp, "\n/* c */\na {}", "a{}")
	expect_css(t, cp, "  a {}", "a{}")
	expect_css(t, cp, "a {}\n/* trailing */", "a{}")
}

@(test)
test_minify_html_script_preserved :: proc(t: ^testing.T) {
	hp, cp := open_parsers(t)
	defer ts.parser_delete(hp)
	defer ts.parser_delete(cp)

	// <script> stays byte-for-byte (whitespace-significant JS).
	input := "<html><body><script>\nconst s = \"a    b\";\n</script></body></html>"
	result, ok := minify_html(hp, cp, input)
	testing.expect(t, ok)
	defer delete(result)
	testing.expect(t, strings.contains(result, "const s = \"a    b\";"))
}
