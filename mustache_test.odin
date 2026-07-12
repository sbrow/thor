#+feature dynamic-literals
#+test
package main

import "core:fmt"
import "core:testing"
import mustache "mustache"

@(test)
test_simple_substitution :: proc(t: ^testing.T) {
	data := map[string]string{"name" = "World"}
	result, err := mustache.render("Hello, {{name}}!", data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "Hello, World!")
}

@(test)
test_bool_section :: proc(t: ^testing.T) {
	data := map[string]bool{"show" = true}
	result, err := mustache.render("{{#show}}visible{{/show}}", data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "visible")
}

@(test)
test_inverted_section :: proc(t: ^testing.T) {
	data := map[string]bool{"show" = false}
	result, err := mustache.render("{{^show}}hidden{{/show}}", data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "hidden")
}

@(test)
test_unescaped :: proc(t: ^testing.T) {
	data := map[string]string{"html" = "<b>bold</b>"}
	result, err := mustache.render("{{{html}}}", data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "<b>bold</b>")
}

@(test)
test_array_iteration :: proc(t: ^testing.T) {
	items := make([dynamic]map[string]string)
	defer delete(items)
	append(&items, map[string]string{"name" = "Alice"})
	append(&items, map[string]string{"name" = "Bob"})

	data := map[string][dynamic]map[string]string{"items" = items}
	result, err := mustache.render("{{#items}}{{name}} {{/items}}", data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "Alice Bob ")
}

@(test)
test_partial :: proc(t: ^testing.T) {
	data := map[string]string{"name" = "Test"}
	partials := map[string]string{"greeting" = "Hello, {{name}}!"}
	result, err := mustache.render("{{>greeting}}", data, partials)
	testing.expect(t, err == nil)
	testing.expect(t, result == "Hello, Test!")
}

@(test)
test_mixed_types :: proc(t: ^testing.T) {
	data := map[string]any{
		"site_title" = "One Idiot Developer",
		"has_date"   = true,
		"date"       = "17 Jul 2025",
	}

	result, err := mustache.render(
		"{{site_title}}: {{#has_date}}{{date}}{{/has_date}}",
		data,
	)
	testing.expect(t, err == nil)
	testing.expect(t, result == "One Idiot Developer: 17 Jul 2025")
}

@(test)
test_nested_context :: proc(t: ^testing.T) {
	page := map[string]string{
		"title" = "My Post",
	}
	data := map[string]any{
		"site_title" = "One Idiot Developer",
		"page"       = page,
	}

	result, err := mustache.render(
		"{{site_title}}: {{#page}}{{title}}{{/page}}",
		data,
	)
	testing.expect(t, err == nil)
	testing.expect(t, result == "One Idiot Developer: My Post")
}

@(test)
test_layout :: proc(t: ^testing.T) {
	layout := `<html><body>{{{content}}}</body></html>`
	template := "<p>Hello!</p>"
	data := map[string]string{}

	result, err := mustache.render_in_layout(template, data, layout)
	testing.expect(t, err == nil)
	testing.expect(t, result == "<html><body><p>Hello!</p></body></html>")
}
