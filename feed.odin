package main

import "core:fmt"
import "core:strings"
import "core:time"

generate_rss :: proc(site: ^Site) -> string {
	sb := strings.builder_make()

	strings.write_string(
		&sb,
		fmt.aprintf(
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
		),
	)

	for page in site.pages {
		if page.section == "" && page._is_index {
			continue
		}

		pub_date := "Mon, 01 Jan 0001 00:00:00 +0000"
		if page.date != "" {
			pub_date = format_rfc822(page.date)
		}

		strings.write_string(
			&sb,
			fmt.aprintf(
				`<item>
<title>%s</title>
<link>%s%s</link>
<pubDate>%s</pubDate>
<guid>%s%s</guid>
<description>%s</description>
</item>
`,
				xml_escape(page.title),
				site.base_url,
				page.permalink,
				pub_date,
				site.base_url,
				page.permalink,
				xml_escape(page.body_html),
			),
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
		lastmod := ""
		if page.date != "" {
			lastmod = fmt.aprintf("<lastmod>%s</lastmod>", page.date)
		}
		strings.write_string(
			&sb,
			fmt.aprintf("<url><loc>%s%s</loc>%s</url>\n", site.base_url, page.permalink, lastmod),
		)
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
		lm := ""
		if section_lastmod != "" {
			lm = fmt.aprintf("<lastmod>%s</lastmod>", section_lastmod)
		}
		strings.write_string(
			&sb,
			fmt.aprintf("<url><loc>%s/%s/</loc>%s</url>\n", site.base_url, section, lm),
		)
	}

	strings.write_string(&sb, "</urlset>")
	return strings.to_string(sb)
}

// TODO: Leaks
format_rfc822 :: proc(iso: string) -> string {
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
	)
}

xml_escape :: proc(s: string) -> string {
	r, _ := strings.replace_all(s, "&", "&amp;")
	r, _ = strings.replace_all(r, "<", "&lt;")
	r, _ = strings.replace_all(r, ">", "&gt;")
	return r
}

