package markdown

import "core:strings"

// generate_toc scans rendered HTML for <h1>-<h6> tags with id attributes and
// builds a nested <ul> table of contents. Returns "" if no headings with IDs
// are found. Must be called after inject_heading_ids.
generate_toc :: proc(html: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)

	current_level := 0
	min_level := 7
	pos := 0

	for {
		idx, level, id, text, next_pos := next_heading(html, pos)
		if level == 0 {
			break
		}
		pos = next_pos

		if level < min_level {
			min_level = level
		}

		if current_level == 0 {
			current_level = level
			strings.write_string(&b, "<ul>\n")
		} else if level > current_level {
			for current_level < level {
				strings.write_string(&b, "<ul>\n")
				current_level += 1
			}
		} else if level < current_level {
			strings.write_string(&b, "</li>\n")
			for current_level > level {
				strings.write_string(&b, "</ul>\n</li>\n")
				current_level -= 1
			}
		} else {
			strings.write_string(&b, "</li>\n")
		}

		strings.write_string(&b, `<li><a href="#`)
		strings.write_string(&b, id)
		strings.write_string(&b, `">`)
		strings.write_string(&b, text)
		strings.write_string(&b, `</a>`)
	}

	if current_level == 0 {
		return ""
	}

	strings.write_string(&b, "</li>\n")
	for current_level > min_level {
		strings.write_string(&b, "</ul>\n</li>\n")
		current_level -= 1
	}
	strings.write_string(&b, "</ul>\n")

	return strings.to_string(b)
}

// next_heading finds the next <hN> tag with an id attribute starting from pos.
// Returns level=0 if none found.
next_heading :: proc(
	html: string,
	start: int,
) -> (
	idx: int,
	level: int,
	id: string,
	text: string,
	next_pos: int,
) {
	i := start
	for i + 3 < len(html) {
		if html[i] == '<' && html[i + 1] == 'h' {
			d := html[i + 2]
			if d >= '1' && d <= '6' {
				level = int(d - '0')
				idx = i
				break
			}
		}
		i += 1
	}

	if level == 0 {
		return 0, 0, "", "", len(html)
	}

	// Find end of opening tag
	tag_end := strings.index_byte(html[idx:], '>')
	if tag_end < 0 {
		return 0, 0, "", "", len(html)
	}
	tag_end += idx

	// Find id="..." within the tag
	tag := html[idx:tag_end + 1]
	id_pos := strings.index(tag, `id="`)
	if id_pos < 0 {
		// No id — skip this heading, continue searching
		return next_heading(html, tag_end + 1)
	}

	id_start := idx + id_pos + 4
	id_end_rel := strings.index_byte(html[id_start:], '"')
	if id_end_rel < 0 {
		return 0, 0, "", "", len(html)
	}
	id = html[id_start:id_start + id_end_rel]

	// Text between > and </hN>
	text_start := tag_end + 1
	close_idx := strings.index(html[text_start:], "</h")
	if close_idx < 0 {
		return 0, 0, "", "", len(html)
	}
	text_end := text_start + close_idx
	text = strip_tags(html[text_start:text_end])

	// Find end of closing tag
	next_pos = text_end + close_tag_len(html, text_end)

	return idx, level, id, text, next_pos
}

// close_tag_len returns the length of the </hN> tag at pos.
close_tag_len :: proc(html: string, pos: int) -> int {
	if pos + 4 > len(html) {
		return 4
	}
	end := strings.index_byte(html[pos:], '>')
	if end < 0 {
		return 4
	}
	return end + 1
}

// strip_tags removes HTML tags from a string, leaving only text content.
strip_tags :: proc(s: string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)

	i := 0
	for i < len(s) {
		if s[i] == '<' {
			end := strings.index_byte(s[i:], '>')
			if end >= 0 {
				i += end + 1
				continue
			}
		}
		strings.write_byte(&b, s[i])
		i += 1
	}
	return strings.to_string(b)
}

