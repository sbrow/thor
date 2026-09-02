#+test
package main

import "core:strings"
import "core:testing"

// ---------------------------------------------------------------------------
// xml_escape
// ---------------------------------------------------------------------------

@(test)
test_xml_escape_passthrough :: proc(t: ^testing.T) {
	testing.expect_value(t, xml_escape(""), "")
	testing.expect_value(t, xml_escape("hello world"), "hello world")
	// UTF-8 multibyte bytes are not metacharacters and pass through untouched.
	testing.expect_value(t, xml_escape("héllo — 世界"), "héllo — 世界")
}

@(test)
test_xml_escape_entities :: proc(t: ^testing.T) {
	testing.expect_value(t, xml_escape("&"), "&amp;")
	testing.expect_value(t, xml_escape("<"), "&lt;")
	testing.expect_value(t, xml_escape(">"), "&gt;")
	// Adjacent specials, and specials at the very start/end of the string.
	testing.expect_value(t, xml_escape("&<>"), "&amp;&lt;&gt;")
	testing.expect_value(t, xml_escape("<a>"), "&lt;a&gt;")
}

@(test)
test_xml_escape_mixed :: proc(t: ^testing.T) {
	testing.expect_value(t, xml_escape("a<b>c&d"), "a&lt;b&gt;c&amp;d")
	testing.expect_value(
		t,
		xml_escape("<p>Tom & Jerry</p>"),
		"&lt;p&gt;Tom &amp; Jerry&lt;/p&gt;",
	)
}

// ---------------------------------------------------------------------------
// format_rfc822
// ---------------------------------------------------------------------------

@(test)
test_format_rfc822_short_passthrough :: proc(t: ^testing.T) {
	// Inputs shorter than a full ISO-8601 timestamp are returned unchanged
	// (and are the input slice itself, so they must not be deleted).
	testing.expect_value(t, format_rfc822("2024"), "2024")
	testing.expect_value(t, format_rfc822(""), "")
}

@(test)
test_format_rfc822_full_date :: proc(t: ^testing.T) {
	// Results are temp-allocated (reset by the test runner), so no delete.
	// 2024-01-15 is a Monday; wall-clock time is preserved and the zone is
	// rendered as an RFC-822 ±HHMM offset.
	testing.expect_value(
		t,
		format_rfc822("2024-01-15T10:30:00Z"),
		"Mon, 15 Jan 2024 10:30:00 +0000",
	)
	testing.expect_value(
		t,
		format_rfc822("2024-01-15T10:30:00+05:30"),
		"Mon, 15 Jan 2024 10:30:00 +0530",
	)
	testing.expect_value(
		t,
		format_rfc822("2024-01-15T10:30:00-08:00"),
		"Mon, 15 Jan 2024 10:30:00 -0800",
	)
}

// ---------------------------------------------------------------------------
// generate_rss
// ---------------------------------------------------------------------------

@(test)
test_generate_rss_structure :: proc(t: ^testing.T) {
	site: Site
	site.title = "My & Site"
	site.description = "Desc <here>"
	site.base_url = "https://example.com"
	site.pages = make(#soa[dynamic]Page)
	defer delete_soa(site.pages)

	// A real content page.
	append(
		&site.pages,
		Page {
			section = "posts",
			title = "First <Post>",
			url = "https://example.com/posts/first/",
			content = "<p>Hello & welcome</p>",
		},
	)
	// The home index page (section == "" && _is_index) must be skipped.
	append(
		&site.pages,
		Page {
			section = "",
			_is_index = true,
			title = "HOME_SHOULD_BE_SKIPPED",
			url = "https://example.com/",
			content = "home",
		},
	)
	// A second content page.
	append(
		&site.pages,
		Page {
			section = "posts",
			title = "Second Post",
			url = "https://example.com/posts/second/",
			content = "plain body",
		},
	)

	rss := generate_rss(&site)
	defer delete(rss)

	// Channel header: site title/description are XML-escaped, link gets a
	// trailing slash, and the atom self-link points at index.xml.
	testing.expect(t, strings.contains(rss, "<title>My &amp; Site</title>"), rss)
	testing.expect(
		t,
		strings.contains(rss, "<description>Desc &lt;here&gt;</description>"),
		rss,
	)
	testing.expect(t, strings.contains(rss, "<link>https://example.com/</link>"), rss)
	testing.expect(
		t,
		strings.contains(rss, `<atom:link href="https://example.com/index.xml"`),
		rss,
	)

	// Exactly two <item>s — the home index page is skipped.
	testing.expect_value(t, strings.count(rss, "<item>"), 2)
	testing.expect(t, !strings.contains(rss, "HOME_SHOULD_BE_SKIPPED"), rss)

	// First item: title and body are XML-escaped, link is verbatim.
	testing.expect(t, strings.contains(rss, "<title>First &lt;Post&gt;</title>"), rss)
	testing.expect(
		t,
		strings.contains(
			rss,
			"<description>&lt;p&gt;Hello &amp; welcome&lt;/p&gt;</description>",
		),
		rss,
	)
	testing.expect(
		t,
		strings.contains(rss, "<link>https://example.com/posts/first/</link>"),
		rss,
	)

	// Undated pages get the sentinel pubDate (no date formatting/allocation).
	testing.expect(
		t,
		strings.contains(rss, "<pubDate>Mon, 01 Jan 0001 00:00:00 +0000</pubDate>"),
		rss,
	)

	// Well-formed at the boundaries.
	testing.expect(t, strings.has_prefix(rss, `<?xml version="1.0"`), rss)
	testing.expect(t, strings.has_suffix(rss, "</channel>\n</rss>"), rss)
}
