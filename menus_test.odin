#+test
package main

import "core:encoding/json"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
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
	testing.expect(t, entry.weight == nil, "string form should have nil weight")
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
	testing.expect(t, entry.weight == nil, "object without weight key should have nil weight")
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
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Test", "/test/")
	menus := parse_page_menus(parse_raw(`{"main": "oops"}`), page, context.allocator)
	testing.expect(t, len(menus) == 1, "entry created with defaults")
	entry, ok := menus["main"]
	testing.expect(t, ok)
	testing.expect(t, entry.weight == nil, "non-object value should have nil weight")
}

@(test)
test_menus_non_numeric_weight :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	page := make_page("Test", "/test/")
	menus := parse_page_menus(parse_raw(`{"main": {"weight": "30"}}`), page, context.allocator)
	entry, ok := menus["main"]
	testing.expect(t, ok)
	testing.expect(t, entry.weight == nil, "non-numeric weight should have nil weight")
}

@(test)
test_menus_empty_title :: proc(t: ^testing.T) {
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
		{name = "Zeta", url = "/z/"},
		{name = "Alpha", url = "/a/", weight = 5},
		{name = "Beta", url = "/b/", weight = 1},
	}
	sort_menu_entries(entries)
	// weight 1 first, then weight 5, then nil (DEFAULT_WEIGHT)
	testing.expect_value(t, entries[0].name, "Beta")
	testing.expect_value(t, entries[1].name, "Alpha")
	testing.expect_value(t, entries[2].name, "Zeta")
}

@(test)
test_sort_equal_weights_alphabetical :: proc(t: ^testing.T) {
	entries := []Menu_Entry {
		{name = "Zebra", url = "/z/"},
		{name = "Apple", url = "/a/"},
		{name = "Mango", url = "/m/"},
	}
	sort_menu_entries(entries)
	testing.expect_value(t, entries[0].name, "Apple")
	testing.expect_value(t, entries[1].name, "Mango")
	testing.expect_value(t, entries[2].name, "Zebra")
}

@(test)
test_sort_mixed_weights :: proc(t: ^testing.T) {
	entries := []Menu_Entry {
		{name = "Charlie", url = "/c/"},
		{name = "Alpha", url = "/a/"},
		{name = "Bravo", url = "/b/", weight = 3},
		{name = "Delta", url = "/d/", weight = 1},
	}
	sort_menu_entries(entries)
	// weight 1 (Delta), weight 3 (Bravo), then nil weight alphabetical (Alpha, Charlie)
	testing.expect_value(t, entries[0].name, "Delta")
	testing.expect_value(t, entries[1].name, "Bravo")
	testing.expect_value(t, entries[2].name, "Alpha")
	testing.expect_value(t, entries[3].name, "Charlie")
}

@(test)
test_sort_explicit_zero_before_nil :: proc(t: ^testing.T) {
	// Explicit weight 0 is distinguishable from unset (nil → DEFAULT_WEIGHT).
	// This is the key behavioral improvement of Maybe(int).
	entries := []Menu_Entry {
		{name = "Unset", url = "/u/"},
		{name = "ExplicitZero", url = "/0/", weight = 0},
		{name = "ExplicitFive", url = "/5/", weight = 5},
	}
	sort_menu_entries(entries)
	// weight 0 first, then weight 5, then nil (DEFAULT_WEIGHT = 10)
	testing.expect_value(t, entries[0].name, "ExplicitZero")
	testing.expect_value(t, entries[1].name, "ExplicitFive")
	testing.expect_value(t, entries[2].name, "Unset")
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
	testing.expect(t, main[1].weight == nil, "entry without weight should be nil")
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
	testing.expect(t, json_get_int(o, "weight") == nil, "missing key should return nil")
}

@(test)
test_json_get_int_non_numeric :: proc(t: ^testing.T) {
	obj, _ := json.parse_string(`{"weight": "5"}`, spec = .JSON)
	defer json.destroy_value(obj)
	o, _ := obj.(json.Object)
	testing.expect(t, json_get_int(o, "weight") == nil, "non-numeric should return nil")
}

// --- sort_pages tests ---

@(test)
test_sort_pages_weight_primary :: proc(t: ^testing.T) {
	pages := make(#soa[dynamic]Page, 0, 3)
	defer delete(pages)
	append(&pages, Page{title = "Gamma", date = "2025-01-03"})
	append(&pages, Page{title = "Alpha", date = "2025-01-01", weight = 5})
	append(&pages, Page{title = "Beta", date = "2025-01-02", weight = 1})

	sort_pages(pages[:])

	// weight 1, weight 5, then nil weight (DEFAULT_WEIGHT)
	testing.expect_value(t, pages.title[0], "Beta")
	testing.expect_value(t, pages.title[1], "Alpha")
	testing.expect_value(t, pages.title[2], "Gamma")
}

@(test)
test_sort_pages_equal_weights_by_date :: proc(t: ^testing.T) {
	pages := make(#soa[dynamic]Page, 0, 3)
	defer delete(pages)
	append(&pages, Page{title = "Old", date = "2025-01-01"})
	append(&pages, Page{title = "New", date = "2025-06-01"})
	append(&pages, Page{title = "Mid", date = "2025-03-01"})

	sort_pages(pages[:])

	// All nil weight → date descending
	testing.expect_value(t, pages.title[0], "New")
	testing.expect_value(t, pages.title[1], "Mid")
	testing.expect_value(t, pages.title[2], "Old")
}

@(test)
test_sort_pages_mixed :: proc(t: ^testing.T) {
	pages := make(#soa[dynamic]Page, 0, 4)
	defer delete(pages)
	append(&pages, Page{title = "DefaultOld", date = "2025-01-01"})
	append(&pages, Page{title = "DefaultNew", date = "2025-06-01"})
	append(&pages, Page{title = "Heavy", date = "2025-03-01", weight = 20})
	append(&pages, Page{title = "Light", date = "2025-02-01", weight = 1})

	sort_pages(pages[:])

	// weight 1, nil weight (DefaultNew by date), nil weight (DefaultOld by date), weight 20
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

// --- warn_duplicate_weights tests ---

@(test)
test_warn_duplicate_weights_explicit :: proc(t: ^testing.T) {
	path := "/tmp/thor_test_warn_explicit.log"
	os.remove(path)
	f, err := os.open(path, os.O_RDWR | os.O_CREATE | os.O_TRUNC)
	if err != nil {
		testing.expect(t, false, "failed to open temp log file")
		return
	}

	logger := log.create_file_logger(f)
	context.logger = logger

	entries := []Menu_Entry {
		{name = "Alpha", url = "/a/", weight = 5},
		{name = "Beta", url = "/b/", weight = 5},
	}
	warn_duplicate_weights("main", entries)

	log.destroy_file_logger(logger)

	data, _ := os.read_entire_file_from_path(path, context.temp_allocator)
	output := string(data)
	os.remove(path)

	testing.expect(t, strings.contains(output, "duplicate weight 5"), "expected weight in warning")
	testing.expect(t, strings.contains(output, "Alpha"), "expected first entry name")
	testing.expect(t, strings.contains(output, "Beta"), "expected second entry name")
	testing.expect(t, strings.contains(output, "'main'"), "expected menu name in warning")
}

@(test)
test_warn_duplicate_weights_nil_not_flagged :: proc(t: ^testing.T) {
	path := "/tmp/thor_test_warn_nil.log"
	os.remove(path)
	f, err := os.open(path, os.O_RDWR | os.O_CREATE | os.O_TRUNC)
	if err != nil {
		testing.expect(t, false, "failed to open temp log file")
		return
	}

	logger := log.create_file_logger(f)
	context.logger = logger

	entries := []Menu_Entry{{name = "Alpha", url = "/a/"}, {name = "Beta", url = "/b/"}}
	warn_duplicate_weights("main", entries)

	log.destroy_file_logger(logger)

	data, _ := os.read_entire_file_from_path(path, context.temp_allocator)
	output := string(data)
	os.remove(path)

	testing.expect(t, output == "", "nil-weight entries should not produce warnings")
}

@(test)
test_warn_duplicate_weights_explicit_default :: proc(t: ^testing.T) {
	path := "/tmp/thor_test_warn_default.log"
	os.remove(path)
	f, err := os.open(path, os.O_RDWR | os.O_CREATE | os.O_TRUNC)
	if err != nil {
		testing.expect(t, false, "failed to open temp log file")
		return
	}

	logger := log.create_file_logger(f)
	context.logger = logger

	entries := []Menu_Entry {
		{name = "Alpha", url = "/a/", weight = 10},
		{name = "Beta", url = "/b/", weight = 10},
	}
	warn_duplicate_weights("main", entries)

	log.destroy_file_logger(logger)

	data, _ := os.read_entire_file_from_path(path, context.temp_allocator)
	output := string(data)
	os.remove(path)

	testing.expect(
		t,
		strings.contains(output, "duplicate weight 10"),
		"explicit weight 10 (== DEFAULT_WEIGHT) should warn — this is the Maybe(int) win",
	)
}
