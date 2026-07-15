#+feature dynamic-literals
#+test
package main

import "core:testing"
import "mustache"

@(test)
test_simple_substitution :: proc(t: ^testing.T) {
	data := map[string]string {
		"name" = "World",
	}
	tpl, _ := mustache.parse("Hello, {{name}}!")
	result, err := mustache.render(tpl, data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "Hello, World!")
}

@(test)
test_bool_section :: proc(t: ^testing.T) {
	data := map[string]bool {
		"show" = true,
	}
	tpl, _ := mustache.parse("{{#show}}visible{{/show}}")
	result, err := mustache.render(tpl, data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "visible")
}

@(test)
test_inverted_section :: proc(t: ^testing.T) {
	data := map[string]bool {
		"show" = false,
	}
	tpl, _ := mustache.parse("{{^show}}hidden{{/show}}")
	result, err := mustache.render(tpl, data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "hidden")
}

@(test)
test_unescaped :: proc(t: ^testing.T) {
	data := map[string]string {
		"html" = "<b>bold</b>",
	}
	tpl, _ := mustache.parse("{{{html}}}")
	result, err := mustache.render(tpl, data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "<b>bold</b>")
}

@(test)
test_array_iteration :: proc(t: ^testing.T) {
	items := make([dynamic]map[string]string)
	defer delete(items)
	append(&items, map[string]string{"name" = "Alice"})
	append(&items, map[string]string{"name" = "Bob"})

	data := map[string][dynamic]map[string]string {
		"items" = items,
	}
	tpl, _ := mustache.parse("{{#items}}{{name}} {{/items}}")
	result, err := mustache.render(tpl, data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "Alice Bob ")
}

@(test)
test_partial :: proc(t: ^testing.T) {
	data := map[string]string {
		"name" = "Test",
	}
	greeting_tpl, _ := mustache.parse("Hello, {{name}}!")
	partials := map[string]mustache.Template {
		"greeting" = greeting_tpl,
	}
	main_tpl, _ := mustache.parse("{{>greeting}}")
	result, err := mustache.render(main_tpl, data, partials)
	testing.expect(t, err == nil)
	testing.expect(t, result == "Hello, Test!")
}

@(test)
test_mixed_types :: proc(t: ^testing.T) {
	data := map[string]any {
		"site_title" = "One Idiot Developer",
		"has_date"   = true,
		"date"       = "17 Jul 2025",
	}

	tpl, _ := mustache.parse("{{site_title}}: {{#has_date}}{{date}}{{/has_date}}")
	result, err := mustache.render(tpl, data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "One Idiot Developer: 17 Jul 2025")
}

@(test)
test_nested_context :: proc(t: ^testing.T) {
	page := map[string]string {
		"title" = "My Post",
	}
	data := map[string]any {
		"site_title" = "One Idiot Developer",
		"page"       = page,
	}

	tpl, _ := mustache.parse("{{site_title}}: {{#page}}{{title}}{{/page}}")
	result, err := mustache.render(tpl, data)
	testing.expect(t, err == nil)
	testing.expect(t, result == "One Idiot Developer: My Post")
}
