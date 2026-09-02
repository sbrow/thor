package main

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"

generate_rss :: proc(site: ^Site) -> string {
	sb := strings.builder_make()

	fmt.sbprintf(
		&sb,
		`<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
<title>%s</title>
<link>%s/</link>
<description>%s</description>
<language>en-us</language>
<atom:link href="%s/index.xml" rel="self" type="application/rss+xml"/>`,
		xml_escape(site.title),
		site.base_url,
		xml_escape(site.description),
		site.base_url,
	)

	for page in site.pages {
		if page.section == "" && page._is_index {
			continue
		}

		pub_date := "Mon, 01 Jan 0001 00:00:00 +0000"
		if page.date != "" {
			pub_date = format_rfc822(page.date)
		}

		fmt.sbprintf(
			&sb,
			`<item>
<title>%s</title>
<link>%s</link>
<pubDate>%s</pubDate>
<guid>%s</guid>
<description>%s</description>
</item>
`,
			xml_escape(page.title),
			page.url,
			pub_date,
			page.url,
			xml_escape(page.content),
		)
	}

	strings.write_string(&sb, "</channel>\n</rss>")
	return strings.to_string(sb)
}

generate_sitemap :: proc(site: ^Site) -> string {
	sb := strings.builder_make()

	strings.write_string(
		&sb,
		`<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
`,
	)

	for page in site.pages {
		fmt.sbprintf(&sb, "<url><loc>%s</loc>", page.url)
		if page.date != "" {
			fmt.sbprintf(&sb, "<lastmod>%s</lastmod>", page.date)
		}
		fmt.sbprintf(&sb, "</url>\n")
	}

	// Section index pages (for sections without an index in content)
	sections := make(map[string]bool)
	defer delete(sections)
	for page in site.pages {
		if page.section != "" && !page._is_index {
			sections[page.section] = true
		}
	}
	for section in sections {
		has_index := false
		for page in site.pages {
			if page.section == section && page._is_index {
				has_index = true
				break
			}
		}
		if has_index {
			continue
		}

		section_lastmod := ""
		for page in site.pages {
			if page.section == section && !page._is_index && page.date > section_lastmod {
				section_lastmod = page.date
			}
		}
		fmt.sbprintf(&sb, "<url><loc>%s/%s/</loc>", site.base_url, section)
		if section_lastmod != "" {
			fmt.sbprintf(&sb, "<lastmod>%s</lastmod>", section_lastmod)
		}
		fmt.sbprintf(&sb, "</url>\n")
	}

	strings.write_string(&sb, "</urlset>")
	return strings.to_string(sb)
}

format_rfc822 :: proc(iso: string, allocator := context.temp_allocator) -> string {
	if len(iso) < 19 {
		// TODO: should indicate error somehow
		return iso
	}

	date, offset, _ := time.iso8601_to_time_and_offset(iso)

	weekday := fmt.tprintf("%s", time.weekday(date))
	month := fmt.tprintf("%s", time.month(date))
	buf: [8]byte
	t := time.to_string_hms(date, buf[:])

	return fmt.aprintf(
		"%s, %02d %s %d %s %3d%2d",
		weekday[:3],
		time.day(date),
		month[:3],
		time.year(date),
		t,
		offset / 60,
		offset % 60,
		allocator = allocator,
	)
}

// xml_escape escapes the XML metacharacters '&', '<' and '>' in s. Only these
// ASCII characters are touched; all other bytes (including UTF-8 multibyte
// sequences) pass through verbatim, so s must already be valid UTF-8.
//
// The result is allocated in `allocator`, which defaults to
// context.temp_allocator — the returned string is only valid until the next
// temp allocator reset, so callers must not retain it across frames.
xml_escape :: proc(
	s: string,
	allocator := context.temp_allocator,
) -> (
	escaped: string,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	sb := strings.builder_make_len_cap(0, len(s), allocator) or_return

	// Single pass over the bytes, copying runs of ordinary text in bulk and
	// emitting an entity for each metacharacter. The switch is both the
	// membership test and the replacement lookup, so no per-match scan.
	start := 0
	for i := 0; i < len(s); i += 1 {
		esc: string
		switch s[i] {
		case '&':
			esc = "&amp;"
		case '<':
			esc = "&lt;"
		case '>':
			esc = "&gt;"
		case:
			continue // ordinary byte: copied as part of the next run
		}
		strings.write_string(&sb, s[start:i]) // run before the metacharacter
		strings.write_string(&sb, esc)
		start = i + 1
	}
	strings.write_string(&sb, s[start:]) // tail
	return strings.to_string(sb), nil
}

