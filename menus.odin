package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

Menu_Entry :: struct {
	name: string,
	url:  string,
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
			if page.menu != "" {
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
		return
	}

	// No config menus — auto-generate, then merge page menus on top
	collect_auto_menus(site)
	merge_page_menus(site)
}

// merge_page_menus collects frontmatter "menu" entries from pages and merges
// them into site.menus (which may already contain auto-generated entries).
// If no pages have "menu" set, this is a no-op.
merge_page_menus :: proc(site: ^Site) {
	alloc := site_allocator(site)

	// Collect page entries by menu name
	page_entries := make(map[string][dynamic]Menu_Entry, 16, alloc)
	for page in site.pages {
		if page.menu == "" {
			continue
		}
		if _, ok := page_entries[page.menu]; !ok {
			page_entries[page.menu] = make([dynamic]Menu_Entry, 0, 4, alloc)
		}
		append(&page_entries[page.menu], Menu_Entry{name = page.title, url = page.permalink})
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
		for page in site.pages {
			if page.section == section && page._is_index {
				url = page.permalink
				if page.title != "" {
					name = page.title
				}
				break
			}
		}
		append(&entries, Menu_Entry{name = name, url = url})
	}

	// Root-level page entries (section = "", not index)
	for page in site.pages {
		if page._is_index || page.section != "" || page.title == "" {
			continue
		}
		append(&entries, Menu_Entry{name = page.title, url = page.permalink})
	}

	if len(entries) == 0 {
		return
	}

	sort_menu_entries(entries[:])
	site.menus = make(map[string][]Menu_Entry, alloc)
	site.menus["main"] = entries[:]
}

sort_menu_entries :: proc(entries: []Menu_Entry) {
	for i in 1 ..< len(entries) {
		key := entries[i]
		j := i - 1
		for j >= 0 && strings.compare(entries[j].name, key.name) > 0 {
			entries[j + 1] = entries[j]
			j -= 1
		}
		entries[j + 1] = key
	}
}

// parse_config_menus converts raw JSON from thor.json into map[string][]Menu_Entry.
// Preserves array order as-declared.
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

			if name == "" {
				log.warnf("menus: '%s' entry %d missing 'name', skipping", menu_name, idx)
				continue
			}

			append(&entries, Menu_Entry{name = name, url = url})
		}
		result[menu_name] = entries[:]
	}

	return result
}
