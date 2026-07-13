package main

import "core:fmt"
import "core:strings"

WEEKDAYS: [7]string = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

generate_rss :: proc(pages: []Page, config: Site) -> string {
	parts: [dynamic]string
	defer delete(parts)

	append(
		&parts,
		fmt.aprintf(
			`<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
<title>%s</title>
<link>%s/</link>
<description>%s</description>
<language>en-us</language>
<atom:link href="%s/index.xml" rel="self" type="application/rss+xml"/>`,
			xml_escape(config.title),
			config.base_url,
			xml_escape(config.description),
			config.base_url,
		),
	)

	for page in pages {
		if page.type == .Home {
			continue
		}

		pub_date := "Mon, 01 Jan 0001 00:00:00 +0000"
		if page.date != "" {
			pub_date = format_rfc822(page.date)
		}

		append(
			&parts,
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
				config.base_url,
				page.permalink,
				pub_date,
				config.base_url,
				page.permalink,
				xml_escape(page.body_html),
			),
		)
	}

	append(&parts, "</channel>\n</rss>")

	return strings.join(parts[:], "")
}

generate_sitemap :: proc(pages: []Page, base_url: string) -> string {
	parts: [dynamic]string
	defer delete(parts)

	append(
		&parts,
		`<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
`,
	)

	for page in pages {
		lastmod := ""
		if page.date != "" {
			lastmod = fmt.aprintf("<lastmod>%s</lastmod>", page.date)
		}
		append(
			&parts,
			fmt.aprintf("<url><loc>%s%s</loc>%s</url>\n", base_url, page.permalink, lastmod),
		)
	}

	// Posts list page
	posts_lastmod := ""
	for page in pages {
		if page.type == .Post && page.date > posts_lastmod {
			posts_lastmod = page.date
		}
	}
	posts_lm := ""
	if posts_lastmod != "" {
		posts_lm = fmt.aprintf("<lastmod>%s</lastmod>", posts_lastmod)
	}
	append(&parts, fmt.aprintf("<url><loc>%s/posts/</loc>%s</url>\n", base_url, posts_lm))

	append(&parts, "</urlset>")

	return strings.join(parts[:], "")
}

format_rfc822 :: proc(iso: string) -> string {
	if len(iso) < 19 {
		return iso
	}

	year :=
		(int(iso[0]) - 0x30) * 1000 +
		(int(iso[1]) - 0x30) * 100 +
		(int(iso[2]) - 0x30) * 10 +
		(int(iso[3]) - 0x30)
	month := (int(iso[5]) - 0x30) * 10 + (int(iso[6]) - 0x30)
	day := (int(iso[8]) - 0x30) * 10 + (int(iso[9]) - 0x30)
	time := iso[11:19]

	// Timezone: -04:00 → -0400
	tz := "+0000"
	if len(iso) >= 25 && (iso[19] == '+' || iso[19] == '-') {
		tz = fmt.tprintf("%c%s%s", iso[19], iso[20:22], iso[23:25])
	}

	// Sakamoto's method for day of week (0=Sunday)
	t := [12]int{0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
	y := year
	if month < 3 {
		y -= 1
	}
	dow := (y + y / 4 - y / 100 + y / 400 + t[month - 1] + day) % 7

	return fmt.aprintf("%s, %d %s %d %s %s", WEEKDAYS[dow], day, MONTHS[month - 1], year, time, tz)
}

xml_escape :: proc(s: string) -> string {
	r, _ := strings.replace_all(s, "&", "&amp;")
	r, _ = strings.replace_all(r, "<", "&lt;")
	r, _ = strings.replace_all(r, ">", "&gt;")
	return r
}

