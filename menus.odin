package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"

DEFAULT_WEIGHT :: 10

Menu_Entry :: struct {
	name:   string,
	url:    string,
	weight: Maybe(int),
}

// parse_page_menus converts raw frontmatter JSON into map[string]Menu_Entry.
// Supports three forms:
//   "menus": "main"                              → {main: {name=title, url=permalink, weight=nil}}
//   "menus": ["main", "footer"]                  → {main: {...}, footer: {...}}
//   "menus": {"main": {"weight": 30}}            → {main: {name=title, url=permalink, weight=30}}
parse_page_menus :: proc(
	raw: json.Value,
	page: Page,
	allocator: mem.Allocator,
) -> map[string]Menu_Entry {
	result: map[string]Menu_Entry

	if raw == nil {
		return nil
	}

	switch v in raw {
	case json.String:
		result = make(map[string]Menu_Entry, allocator)
		result[string(v)] = Menu_Entry {
			name = page.title,
			url  = page.permalink,
		}

	case json.Array:
		result = make(map[string]Menu_Entry, allocator)
		for item in v {
			if s, ok := item.(json.String); ok {
				result[string(s)] = Menu_Entry {
					name = page.title,
					url  = page.permalink,
				}
			} else {
				log.warnf("menus: ignoring non-string item in menus array: %v", item)
			}
		}

	case json.Object:
		result = make(map[string]Menu_Entry, allocator)
		for menu_name, entry_val in v {
			weight: Maybe(int) = nil
			if entry_obj, ok := entry_val.(json.Object); ok {
				if w, ok := entry_obj["weight"]; ok {
					switch wval in w {
					case json.Integer:
						weight = int(wval)
					case json.Float:
						weight = int(wval)
					case json.Boolean, json.String, json.Array, json.Object, json.Null:
						log.warnf(
							"menus: '%s' entry 'weight' must be a number, got %v",
							menu_name,
							w,
						)
					}
				}
				if _, has_name := entry_obj["name"]; has_name {
					log.warnf(
						"menus: '%s' entry 'name' override not yet supported, ignoring",
						menu_name,
					)
				}
				if _, has_url := entry_obj["url"]; has_url {
					log.warnf(
						"menus: '%s' entry 'url' override not yet supported, ignoring",
						menu_name,
					)
				}
			} else {
				log.warnf(
					"menus: '%s' entry must be an object, got %v, using defaults",
					menu_name,
					entry_val,
				)
			}
			result[menu_name] = Menu_Entry {
				name   = page.title,
				url    = page.permalink,
				weight = weight,
			}
		}

	case json.Null:
		return nil

	case json.Integer, json.Float, json.Boolean:
		log.warnf("menus: expected string, array, or object, got %v", raw)
		return nil
	}

	if page.title == "" {
		log.warnf("menus: page '%s' has no title, menu entry will be blank", page.permalink)
	}

	return result
}

// build_menus populates site.menus:
//   1. Config menus (thor.json "menus" key present) — exclusive, preserves array order
//   2. Auto-menus (sections + root-level pages) + page frontmatter menus — merged, sorted
//
// If "menus" is present but empty ({}) it means explicit opt-out: no menus.
// Config menus cannot be mixed with page frontmatter menus (error).
build_menus :: proc(site: ^Site) {
	if site.menus != nil {
		has_menus := false
		for page in site.pages {
			if len(page.menus) > 0 {
				has_menus = true
				break
			}
		}

		// Already populated from config in site_apply_config
		if len(site.menus) == 0 {
			// Explicit opt-out ("menus": {})
			if has_menus {
				log.warnf(
					"menus: config has empty menus but pages have frontmatter menu entries; ignoring page menus",
				)
			}
			return
		}
		// Config menus active
		if has_menus {
			log.fatalf("menus: cannot mix config menus with frontmatter menus")
			os.exit(1)
		}
		warn_all_duplicate_weights(site)
		return
	}

	// No config menus — auto-generate, then merge page menus on top
	collect_auto_menus(site)
	merge_page_menus(site)
	warn_all_duplicate_weights(site)
}

// merge_page_menus collects frontmatter menu entries from pages and merges
// them into site.menus (which may already contain auto-generated entries).
// If no pages have menus set, this is a no-op.
merge_page_menus :: proc(site: ^Site) {
	alloc := site_allocator(site)

	// Collect page entries by menu name
	page_entries := make(map[string][dynamic]Menu_Entry, 16, alloc)
	for page in site.pages {
		for menu_name, entry in page.menus {
			if _, ok := page_entries[menu_name]; !ok {
				page_entries[menu_name] = make([dynamic]Menu_Entry, 0, 4, alloc)
			}
			// Effective weight: per-menu weight if set, else page.weight
			effective := entry.weight
			if effective == nil {
				effective = page.weight
			}
			append(
				&page_entries[menu_name],
				Menu_Entry{name = entry.name, url = entry.url, weight = effective},
			)
		}
	}

	if len(page_entries) == 0 {
		return
	}

	if site.menus == nil {
		site.menus = make(map[string][]Menu_Entry, alloc)
	}

	for menu_name, entries in page_entries {
		sort_menu_entries(entries[:])
		if existing, ok := site.menus[menu_name]; ok {
			// Merge with existing auto-generated entries
			merged := make([dynamic]Menu_Entry, 0, len(existing) + len(entries), alloc)
			append(&merged, ..existing)
			append(&merged, ..entries[:])
			sort_menu_entries(merged[:])
			site.menus[menu_name] = merged[:]
		} else {
			site.menus[menu_name] = entries[:]
		}
	}
}

collect_auto_menus :: proc(site: ^Site) {
	alloc := site_allocator(site)
	sections: map[string]bool

	for page in site.pages {
		if page._is_index {
			continue
		}
		if page.section != "" {
			sections[page.section] = true
		}
	}

	entries := make([dynamic]Menu_Entry, 0, 8, alloc)

	// Section entries (one per section directory)
	for section in sections {
		name := to_title_case(section, alloc)
		url := fmt.aprintf("/%s/", section, allocator = alloc)
		skip := false
		for page in site.pages {
			if page.section == section && page._is_index {
				url = page.permalink
				if page.title != "" {
					name = page.title
				}
				if _, has_main := page.menus["main"]; has_main {
					skip = true
				}
				break
			}
		}
		if !skip {
			append(&entries, Menu_Entry{name = name, url = url})
		}
	}

	// Root-level page entries (section = "", not index)
	for page in site.pages {
		if page._is_index || page.section != "" || page.title == "" {
			continue
		}
		if _, has_main := page.menus["main"]; has_main {
			continue
		}
		append(&entries, Menu_Entry{name = page.title, url = page.permalink, weight = page.weight})
	}

	if len(entries) == 0 {
		return
	}

	sort_menu_entries(entries[:])
	site.menus = make(map[string][]Menu_Entry, alloc)
	site.menus["main"] = entries[:]
}

compare_menu_entries :: proc(a, b: Menu_Entry) -> int {
	aw := a.weight.? or_else DEFAULT_WEIGHT
	bw := b.weight.? or_else DEFAULT_WEIGHT
	if aw != bw do return aw - bw
	a_set := a.weight != nil
	b_set := b.weight != nil
	if a_set != b_set {
		return a_set ? -1 : 1
	}
	return strings.compare(a.name, b.name)
}

sort_menu_entries :: proc(entries: []Menu_Entry) {
	for i in 1 ..< len(entries) {
		key := entries[i]
		j := i - 1
		for j >= 0 && compare_menu_entries(entries[j], key) > 0 {
			entries[j + 1] = entries[j]
			j -= 1
		}
		entries[j + 1] = key
	}
}

// warn_duplicate_weights logs a warning for each pair of adjacent entries
// (pre-sorted) that have the same explicitly-set weight. Entries with nil
// weight (unset/default) are never flagged.
warn_duplicate_weights :: proc(menu_name: string, entries: []Menu_Entry) {
	for i in 0 ..< len(entries) - 1 {
		if entries[i].weight != nil && entries[i].weight == entries[i + 1].weight {
			log.warnf(
				"menus('%s'): '%s' and '%s' share the same menu weight (%d).",
				menu_name,
				entries[i].name,
				entries[i + 1].name,
				entries[i].weight,
			)
		}
	}
}

warn_all_duplicate_weights :: proc(site: ^Site) {
	for menu_name, entries in site.menus {
		warn_duplicate_weights(menu_name, entries)
	}
}

// parse_config_menus converts raw JSON from thor.json into map[string][]Menu_Entry.
// Entries are sorted by weight, then name.
parse_config_menus :: proc(
	raw: json.Value,
	allocator := context.allocator,
) -> map[string][]Menu_Entry {
	obj, ok := raw.(json.Object)
	if !ok || len(obj) == 0 {
		return nil
	}

	result := make(map[string][]Menu_Entry, allocator)
	for menu_name, menu_val in obj {
		arr, ok := menu_val.(json.Array)
		if !ok {
			log.warnf("menus: '%s' is not an array, skipping", menu_name)
			continue
		}

		entries := make([dynamic]Menu_Entry, 0, len(arr), allocator)
		for item, idx in arr {
			entry_obj, ok := item.(json.Object)
			if !ok {
				log.warnf("menus: '%s' entry %d is not an object, skipping", menu_name, idx)
				continue
			}

			name := ""
			url := ""
			weight: Maybe(int) = nil

			if v, ok := entry_obj["name"]; ok {
				if s, ok2 := v.(json.String); ok2 {
					name = string(s)
				} else {
					log.warnf(
						"menus: '%s' entry %d: 'name' must be a string, got %v, skipping",
						menu_name,
						idx,
						v,
					)
					continue
				}
			}

			if v, ok := entry_obj["url"]; ok {
				if s, ok2 := v.(json.String); ok2 {
					url = string(s)
				} else {
					log.warnf(
						"menus: '%s' entry %d: 'url' must be a string, got %v, skipping",
						menu_name,
						idx,
						v,
					)
					continue
				}
			}

			if v, ok := entry_obj["weight"]; ok {
				switch wval in v {
				case json.Integer:
					weight = int(wval)
				case json.Float:
					weight = int(wval)
				case json.Null, json.Boolean, json.String, json.Array, json.Object:
					log.warnf(
						"menus: '%s' entry %d: 'weight' must be a number, got %v",
						menu_name,
						idx,
						v,
					)
				}
			}

			if name == "" {
				log.warnf("menus: '%s' entry %d missing 'name', skipping", menu_name, idx)
				continue
			}

			append(&entries, Menu_Entry{name = name, url = url, weight = weight})
		}
		sort_menu_entries(entries[:])
		result[menu_name] = entries[:]
	}

	return result
}
