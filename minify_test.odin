#+test
package main

import "core:strings"
import "core:sync"
import "core:testing"
import "treesitter"

// The treesitter parser store is normally initialized by main() via
// treesitter.init_persistent(); the test runner never calls main. init_once
// ensures it happens exactly once no matter which test thread arrives first,
// and preloads the builtin parsers on that single thread — after which the
// concurrent tests only *read* the cache (the unlocked writes in ensure_parser
// are what corrupt it, not reads).
@(private = "file")
init_once: sync.Once

setup_treesitter :: proc() {
	sync.once_do(&init_once, proc() {
		treesitter.init_persistent()
		treesitter.ensure_parser("html")
		treesitter.ensure_parser("css")
	})
}

// The builtin parsers are cached and shared per-language, and tree-sitter
// parsers are not reentrant — concurrent parser_parse_string corrupts their
// internal subtree pool. The multi-threaded test runner would otherwise race,
// so serialize parser use behind this mutex. (Production renders on a single
// thread, so it needs no such lock.)
@(private = "file")
parse_mu: sync.Mutex

ts_minify_html :: proc(s: string) -> string {
	sync.mutex_lock(&parse_mu)
	defer sync.mutex_unlock(&parse_mu)
	return minify_html(s)
}

ts_minify_css :: proc(s: string) -> string {
	sync.mutex_lock(&parse_mu)
	defer sync.mutex_unlock(&parse_mu)
	return minify_css(s)
}

// --- minify_html: inline <style> bodies get CSS-minified ---

@(test)
test_minify_html_inline_style :: proc(t: ^testing.T) {
	setup_treesitter()
	input := `<html><head><style>
body {
  color:  red;
}
</style></head><body><p>hi</p></body></html>`
	result := ts_minify_html(input)

	// The CSS body is collapsed by minify_css (delimiters lose surrounding
	// whitespace)...
	testing.expect(t, strings.contains(result, "body{color:red;}"))
	// ...while the <style> tags themselves survive.
	testing.expect(t, strings.contains(result, "<style>"))
	testing.expect(t, strings.contains(result, "</style>"))
}

@(test)
test_minify_html_empty_style :: proc(t: ^testing.T) {
	setup_treesitter()
	// An empty <style></style> has no raw_text child; must not crash.
	input := `<html><head><style></style></head><body></body></html>`
	result := ts_minify_html(input)
	testing.expect(t, strings.contains(result, "<style></style>"))
}

// --- minify_css: whitespace around stripped comments / leading edge ---

@(test)
test_minify_css_leading_and_comment :: proc(t: ^testing.T) {
	setup_treesitter()
	// Leading whitespace and a comment between two whitespace runs must not
	// leave a leading space or a doubled space.
	testing.expect_value(t, ts_minify_css("\n/* c */\na {}"), "a{}")
	testing.expect_value(t, ts_minify_css("  a {}"), "a{}")
	testing.expect_value(t, ts_minify_css("a {}\n/* trailing */"), "a{}")
}

@(test)
test_minify_html_script_preserved :: proc(t: ^testing.T) {
	setup_treesitter()
	// <script> stays byte-for-byte (whitespace-significant JS).
	input := "<html><body><script>\nconst s = \"a    b\";\n</script></body></html>"
	result := ts_minify_html(input)
	testing.expect(t, strings.contains(result, "const s = \"a    b\";"))
}
