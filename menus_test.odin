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

// --- json_get_int tests ---

@(test)
test_json_get_int_integer :: proc(t: ^testing.T) {
	obj, _ := json.parse_string(`{"weight": 5}`, spec = .JSON)
	defer json.destroy_value(obj)
	o, _ := obj.(json.Object)
	testing.expect_value(t, json_get_int(o, "weight"), 5)
}

@(test)
test_json_get_int_float :: proc(t: ^testing.T) {
	obj, _ := json.parse_string(`{"weight": 5.0}`, spec = .JSON)
	defer json.destroy_value(obj)
	o, _ := obj.(json.Object)
	testing.expect_value(t, json_get_int(o, "weight"), 5)
}

@(test)
test_json_get_int_missing :: proc(t: ^testing.T) {
	obj, _ := json.parse_string(`{}`, spec = .JSON)
	defer json.destroy_value(obj)
	o, _ := obj.(json.Object)
	testing.expect_value(t, json_get_int(o, "weight"), 0)
}

@(test)
test_json_get_int_non_numeric :: proc(t: ^testing.T) {
	obj, _ := json.parse_string(`{"weight": "5"}`, spec = .JSON)
	defer json.destroy_value(obj)
	o, _ := obj.(json.Object)
	testing.expect_value(t, json_get_int(o, "weight"), 0)
}

// --- sort_pages tests ---

@(test)
test_sort_pages_weight_primary :: proc(t: ^testing.T) {
	pages := make(#soa[dynamic]Page, 0, 3)
	defer delete(pages)
	append(&pages, Page{title = "Gamma", date = "2025-01-03", weight = DEFAULT_WEIGHT})
	append(&pages, Page{title = "Alpha", date = "2025-01-01", weight = 5})
	append(&pages, Page{title = "Beta", date = "2025-01-02", weight = 1})

	sort_pages(pages[:])

	// weight 1, weight 5, then default weight 10
	testing.expect_value(t, pages.title[0], "Beta")
	testing.expect_value(t, pages.title[1], "Alpha")
	testing.expect_value(t, pages.title[2], "Gamma")
}

@(test)
test_sort_pages_equal_weights_by_date :: proc(t: ^testing.T) {
	pages := make(#soa[dynamic]Page, 0, 3)
	defer delete(pages)
	append(&pages, Page{title = "Old", date = "2025-01-01", weight = DEFAULT_WEIGHT})
	append(&pages, Page{title = "New", date = "2025-06-01", weight = DEFAULT_WEIGHT})
	append(&pages, Page{title = "Mid", date = "2025-03-01", weight = DEFAULT_WEIGHT})

	sort_pages(pages[:])

	// All same weight → date descending
	testing.expect_value(t, pages.title[0], "New")
	testing.expect_value(t, pages.title[1], "Mid")
	testing.expect_value(t, pages.title[2], "Old")
}

@(test)
test_sort_pages_mixed :: proc(t: ^testing.T) {
	pages := make(#soa[dynamic]Page, 0, 4)
	defer delete(pages)
	append(&pages, Page{title = "DefaultOld", date = "2025-01-01", weight = DEFAULT_WEIGHT})
	append(&pages, Page{title = "DefaultNew", date = "2025-06-01", weight = DEFAULT_WEIGHT})
	append(&pages, Page{title = "Heavy", date = "2025-03-01", weight = 20})
	append(&pages, Page{title = "Light", date = "2025-02-01", weight = 1})

	sort_pages(pages[:])

	// weight 1, weight 10 (DefaultNew by date), weight 10 (DefaultOld by date), weight 20
	testing.expect_value(t, pages.title[0], "Light")
	testing.expect_value(t, pages.title[1], "DefaultNew")
	testing.expect_value(t, pages.title[2], "DefaultOld")
	testing.expect_value(t, pages.title[3], "Heavy")
}

// --- merge_page_menus effective weight tests ---

@(test)
test_merge_page_menus_weight_fallback :: proc(t: ^testing.T) {
	site: Site
	mem.dynamic_arena_init(&site.arena)
	defer mem.dynamic_arena_destroy(&site.arena)
	context.allocator = site_allocator(&site)

	page := make_page("Test", "/test/")
	page.weight = 3
	page.menus = parse_page_menus(parse_raw(`"main"`), page, site_allocator(&site))

	site.pages = make(#soa[dynamic]Page, 0, 1, site_allocator(&site))
	append(&site.pages, page)

	// Don't call collect_auto_menus — test merge_page_menus in isolation
	merge_page_menus(&site)

	main, ok := site.menus["main"]
	testing.expect(t, ok)
	testing.expect(t, len(main) == 1, "expected exactly 1 entry")
	testing.expect_value(t, main[0].name, "Test")
	testing.expect_value(t, main[0].weight, 3)
}

@(test)
test_auto_menus_no_duplicate_with_frontmatter :: proc(t: ^testing.T) {
	site: Site
	mem.dynamic_arena_init(&site.arena)
	defer mem.dynamic_arena_destroy(&site.arena)
	context.allocator = site_allocator(&site)

	// Root-level page with explicit "menus": "main"
	page := make_page("Ideas", "/ideas/")
	page.menus = parse_page_menus(parse_raw(`"main"`), page, site_allocator(&site))

	site.pages = make(#soa[dynamic]Page, 0, 1, site_allocator(&site))
	append(&site.pages, page)

	collect_auto_menus(&site)
	merge_page_menus(&site)

	main, ok := site.menus["main"]
	testing.expect(t, ok)
	testing.expect(t, len(main) == 1, "expected exactly 1 entry (no duplicate)")
	testing.expect_value(t, main[0].name, "Ideas")
}
