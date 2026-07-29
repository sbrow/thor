package markdown

import "core:fmt"
import "core:log"
import "core:strings"

// A hypothetical maximum slug length.
// May be enforced in a later version (for performance)
MAX_SLUG_LENGTH :: #config(MAX_SLUG_LENGTH, 255)

inject_heading_ids :: proc(html: string, allocator := context.allocator) -> string {
	sb := strings.builder_make_len_cap(0, len(html) + 256, allocator)
	defer strings.builder_destroy(&sb)

	seen := make(map[string]bool, 8, context.temp_allocator)
	empty_count := 0

	pos := 0
	for {
		h_start := find_heading_open(html, pos)
		if h_start < 0 {
			strings.write_string(&sb, html[pos:])
			break
		}

		if h_start > pos {
			strings.write_string(&sb, html[pos:h_start])
		}

		level := int(html[h_start + 2] - '0')

		close_buf: [5]u8
		close_buf[0] = '<'; close_buf[1] = '/'; close_buf[2] = 'h'
		close_buf[3] = html[h_start + 2]
		close_buf[4] = '>'
		close_tag := string(close_buf[:])

		close_rel := strings.index(html[h_start:], close_tag)
		if close_rel < 0 {
			strings.write_string(&sb, html[h_start:])
			break
		}

		open_tag_end := h_start + 4
		close_start := h_start + close_rel
		close_end := close_start + 5

		inner_html := html[open_tag_end:close_start]

		text := extract_plain_text(inner_html, context.temp_allocator)
		slug := slugify(text)
		if len(slug) == 0 {
			empty_count += 1
			slug = fmt.tprintf("section-%d", empty_count)
		}
		slug = make_unique(slug, &seen)

		fmt.sbprintf(&sb, `<h%d id="%s">`, level, slug)
		strings.write_string(&sb, inner_html)
		strings.write_string(&sb, close_tag)

		pos = close_end
	}

	return strings.to_string(sb)
}

find_heading_open :: proc(html: string, start: int) -> int {
	pos := start
	for pos < len(html) - 3 {
		if html[pos] == '<' &&
		   html[pos + 1] == 'h' &&
		   html[pos + 2] >= '1' &&
		   html[pos + 2] <= '6' &&
		   html[pos + 3] == '>' {
			return pos
		}
		pos += 1
	}
	return -1
}

extract_plain_text :: proc(html: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	defer strings.builder_destroy(&sb)

	in_tag := false
	i := 0
	for i < len(html) {
		c := html[i]
		if in_tag {
			if c == '>' {
				in_tag = false
			}
			i += 1
			continue
		}
		if c == '<' {
			in_tag = true
			i += 1
			continue
		}
		if c == '&' {
			semi := strings.index(html[i:], ";")
			if semi > 0 && semi <= 5 {
				entity := html[i:i + semi + 1]
				replacement := ""
				switch entity {
				case "&amp;":
					replacement = "&"
				case "&lt;":
					replacement = "<"
				case "&gt;":
					replacement = ">"
				case "&quot;":
					replacement = "\""
				case "&#39;", "&apos;":
					replacement = "'"
				case:
					replacement = ""
				}
				if replacement != "" {
					strings.write_string(&sb, replacement)
					i += semi + 1
					continue
				}
			}
			strings.write_byte(&sb, '&')
			i += 1
			continue
		}
		strings.write_byte(&sb, c)
		i += 1
	}

	return strings.to_string(sb)
}

slugify :: proc(text: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make_len_cap(0, 255, allocator)
	defer strings.builder_destroy(&sb)

	has_hyphen := false

	for i in 0 ..< len(text) {
		c := text[i]
		if c >= 'A' && c <= 'Z' {
			strings.write_byte(&sb, c + 32)
			has_hyphen = false
		} else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
			strings.write_byte(&sb, c)
			has_hyphen = false
		} else {
			if !has_hyphen {
				strings.write_byte(&sb, '-')
				has_hyphen = true
			}
		}
	}

	result := strings.to_string(sb)
	if len(result) > 0 && result[len(result) - 1] == '-' {
		result = result[:len(result) - 1]
	}

	if len(result) > MAX_SLUG_LENGTH {
		log.warnf(
			"Long slug detected (%d > %d). " +
			"This may break in later versions of thor. " +
			"slug=%s input=\"%s\"",
			len(result),
			MAX_SLUG_LENGTH,
			result,
			text,
		)
	}
	return result
}

make_unique :: proc(slug: string, seen: ^map[string]bool) -> string {
	if _, ok := seen^[slug]; !ok {
		seen^[slug] = true
		return slug
	}
	n := 1
	for {
		candidate := fmt.tprintf("%s-%d", slug, n)
		if _, ok := seen^[candidate]; !ok {
			seen^[candidate] = true
			return candidate
		}
		n += 1
	}
	return ""
}
