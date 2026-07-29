#+test
package main

import "core:encoding/json"
import "core:log"
import "core:mem"
import "core:testing"

make_page :: proc(title: string, permalink: string) -> Page {
	return Page{title = title, permalink = permalink}
}

parse_raw :: proc(s: string) -> json.Value {
	v, _ := json.parse_string(s, spec = .JSON)
	return v
}


@(test)
test_menus_string_form :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("About", "/about/")
	menus := parse_page_menus(parse_raw(`"main"`), page, context.allocator)
	testing.expect(t, len(menus) == 1, "expected 1 menu")
	entry, ok := menus["main"]
	testing.expect(t, ok, "expected 'main' menu")
	testing.expect_value(t, entry.name, "About")
	testing.expect_value(t, entry.url, "/about/")
	testing.expect_value(t, entry.weight, DEFAULT_WEIGHT)
}

@(test)
test_menus_array_form :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Contact", "/contact/")
	menus := parse_page_menus(parse_raw(`["main", "footer"]`), page, context.allocator)
	testing.expect(t, len(menus) == 2, "expected 2 menus")

	main, ok1 := menus["main"]
	testing.expect(t, ok1)
	testing.expect_value(t, main.name, "Contact")

	footer, ok2 := menus["footer"]
	testing.expect(t, ok2)
	testing.expect_value(t, footer.name, "Contact")
}

@(test)
test_menus_object_with_weight :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Posts", "/posts/")
	menus := parse_page_menus(parse_raw(`{"main": {"weight": 30}}`), page, context.allocator)
	testing.expect(t, len(menus) == 1)
	entry, ok := menus["main"]
	testing.expect(t, ok)
	testing.expect_value(t, entry.weight, 30)
	testing.expect_value(t, entry.name, "Posts")
}

@(test)
test_menus_object_no_weight :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("About", "/about/")
	menus := parse_page_menus(parse_raw(`{"main": {}}`), page, context.allocator)
	testing.expect(t, len(menus) == 1)
	entry, ok := menus["main"]
	testing.expect(t, ok)
	testing.expect_value(t, entry.weight, DEFAULT_WEIGHT)
}

@(test)
test_menus_nil_input :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Test", "/test/")
	menus := parse_page_menus(nil, page, context.allocator)
	testing.expect(t, menus == nil, "nil input should return nil")
}

@(test)
test_menus_invalid_type :: proc(t: ^testing.T) {
	context.logger = log.nil_logger()
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Test", "/test/")
	menus := parse_page_menus(parse_raw(`42`), page, context.allocator)
	testing.expect(t, menus == nil, "integer should return nil")
}

@(test)
test_menus_array_non_string :: proc(t: ^testing.T) {
	context.logger = log.nil_logger()
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Test", "/test/")
	menus := parse_page_menus(parse_raw(`["main", 42, "footer"]`), page, context.allocator)
	testing.expect(t, len(menus) == 2, "42 should be dropped")
	_, ok1 := menus["main"]
	testing.expect(t, ok1)
	_, ok2 := menus["footer"]
	testing.expect(t, ok2)
}

@(test)
test_menus_object_non_object_value :: proc(t: ^testing.T) {
	context.logger = log.nil_logger()
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Test", "/test/")
	menus := parse_page_menus(parse_raw(`{"main": "oops"}`), page, context.allocator)
	testing.expect(t, len(menus) == 1, "entry created with defaults")
	entry, ok := menus["main"]
	testing.expect(t, ok)
	testing.expect_value(t, entry.weight, DEFAULT_WEIGHT)
}

@(test)
test_menus_non_numeric_weight :: proc(t: ^testing.T) {
	context.logger = log.nil_logger()
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Test", "/test/")
	menus := parse_page_menus(parse_raw(`{"main": {"weight": "30"}}`), page, context.allocator)
	entry, ok := menus["main"]
	testing.expect(t, ok)
	testing.expect_value(t, entry.weight, DEFAULT_WEIGHT)
}

@(test)
test_menus_empty_title :: proc(t: ^testing.T) {
	context.logger = log.nil_logger()
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("", "/test/")
	menus := parse_page_menus(parse_raw(`"main"`), page, context.allocator)
	testing.expect(t, len(menus) == 1)
	entry, ok := menus["main"]
	testing.expect(t, ok)
	testing.expect_value(t, entry.name, "")
}

@(test)
test_menus_object_with_float_weight :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Test", "/test/")
	menus := parse_page_menus(parse_raw(`{"main": {"weight": 15.0}}`), page, context.allocator)
	entry, ok := menus["main"]
	testing.expect(t, ok)
	testing.expect_value(t, entry.weight, 15)
}

@(test)
test_menus_null_json :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Test", "/test/")
	menus := parse_page_menus(parse_raw(`null`), page, context.allocator)
	testing.expect(t, menus == nil, "null JSON should return nil")
}

// --- sort_menu_entries tests ---

@(test)
test_sort_weight_orders_correctly :: proc(t: ^testing.T) {
	entries := []Menu_Entry {
		{name = "Zeta", url = "/z/", weight = DEFAULT_WEIGHT},
		{name = "Alpha", url = "/a/", weight = 5},
		{name = "Beta", url = "/b/", weight = 1},
	}
	sort_menu_entries(entries)
	// weight 1 first, then weight 5, then default weight 10
	testing.expect_value(t, entries[0].name, "Beta")
	testing.expect_value(t, entries[1].name, "Alpha")
	testing.expect_value(t, entries[2].name, "Zeta")
}

@(test)
test_sort_equal_weights_alphabetical :: proc(t: ^testing.T) {
	entries := []Menu_Entry {
		{name = "Zebra", url = "/z/", weight = DEFAULT_WEIGHT},
		{name = "Apple", url = "/a/", weight = DEFAULT_WEIGHT},
		{name = "Mango", url = "/m/", weight = DEFAULT_WEIGHT},
	}
	sort_menu_entries(entries)
	testing.expect_value(t, entries[0].name, "Apple")
	testing.expect_value(t, entries[1].name, "Mango")
	testing.expect_value(t, entries[2].name, "Zebra")
}

@(test)
test_sort_mixed_weights :: proc(t: ^testing.T) {
	entries := []Menu_Entry {
		{name = "Charlie", url = "/c/", weight = DEFAULT_WEIGHT},
		{name = "Alpha", url = "/a/", weight = DEFAULT_WEIGHT},
		{name = "Bravo", url = "/b/", weight = 3},
		{name = "Delta", url = "/d/", weight = 1},
	}
	sort_menu_entries(entries)
	// weight 1 (Delta), weight 3 (Bravo), then default weight alphabetical (Alpha, Charlie)
	testing.expect_value(t, entries[0].name, "Delta")
	testing.expect_value(t, entries[1].name, "Bravo")
	testing.expect_value(t, entries[2].name, "Alpha")
	testing.expect_value(t, entries[3].name, "Charlie")
}

@(test)
test_config_weight_parsing_and_sort :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	raw := parse_raw(
		`{
		"main": [
			{"name": "Heavy", "url": "/h/", "weight": 20},
			{"name": "Light", "url": "/l/", "weight": 1},
			{"name": "Default", "url": "/d/"}
		]
	}`,
	)

	menus := parse_config_menus(raw, context.allocator)
	main, ok := menus["main"]
	testing.expect(t, ok)
	testing.expect(t, len(main) == 3)
	testing.expect_value(t, main[0].name, "Light")
	testing.expect_value(t, main[0].weight, 1)
	testing.expect_value(t, main[1].name, "Default")
	testing.expect_value(t, main[1].weight, DEFAULT_WEIGHT)
	testing.expect_value(t, main[2].name, "Heavy")
	testing.expect_value(t, main[2].weight, 20)
}
