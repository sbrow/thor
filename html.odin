package main

import "core:strings"

strip_html_tags :: proc(s: string, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	defer strings.builder_destroy(&sb)

	in_tag := false
	start := 0
	for i in 0 ..< len(s) {
		if s[i] == '<' && !in_tag {
			if i > start {
				strings.write_string(&sb, s[start:i])
			}
			in_tag = true
		} else if s[i] == '>' && in_tag {
			in_tag = false
			start = i + 1
		}
	}
	if start == 0 {
		return s
	}
	if !in_tag && start < len(s) {
		strings.write_string(&sb, s[start:])
	}
	return strings.to_string(sb)
}

unescape_html :: proc(s: string) -> string {
	sb := strings.builder_make_len_cap(0, len(s))
	defer strings.builder_destroy(&sb)

	start := 0
	for i in 0 ..< len(s) {
		if s[i] != '&' {
			continue
		}
		semi := strings.index(s[i:], ";")
		if semi < 0 {
			break
		}
		entity := s[i:i + semi + 1]
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
			continue
		}
		if i > start {
			strings.write_string(&sb, s[start:i])
		}
		strings.write_string(&sb, replacement)
		start = i + semi + 1
	}
	if start == 0 {
		return s
	}
	if start < len(s) {
		strings.write_string(&sb, s[start:])
	}
	return strings.to_string(sb)
}

// generate_summary truncates an HTML string to the first max_words words.
// Walks forward counting whitespace→text transitions, skipping tag interiors
// so spaces inside attributes don't count. Returns a substring of the
// original — zero allocation. Mirrors Hugo's default (70 words).
generate_summary :: proc(html: string, max_words: int = 70) -> string {
	if max_words <= 0 {
		return ""
	}
	word_count := 0
	in_word := false
	in_tag := false
	for i in 0 ..< len(html) {
		c := html[i]
		if in_tag {
			if c == '>' {
				in_tag = false
			}
			continue
		}
		if c == '<' {
			in_tag = true
			if in_word {
				word_count += 1
				if word_count >= max_words {
					return html[:i]
				}
				in_word = false
			}
			continue
		}
		is_space := c == ' ' || c == '\n' || c == '\t' || c == '\r'
		if is_space {
			if in_word {
				word_count += 1
				if word_count >= max_words {
					return html[:i]
				}
				in_word = false
			}
		} else {
			in_word = true
		}
	}
	return html
}

// generate_description converts an HTML fragment to plain text by stripping
// tags, decoding entities, and collapsing whitespace. Emits a space when
// exiting any tag so block-level boundaries aren't lost. Intended for OG
// descriptions — operate on the output of generate_summary for bounded input.
generate_description :: proc(html: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make_len_cap(0, len(html), allocator)
	defer strings.builder_destroy(&sb)

	in_tag := false
	prev_was_space := true
	run_start := 0
	i := 0
	for i < len(html) {
		c := html[i]
		if in_tag {
			if c == '>' {
				in_tag = false
				if !prev_was_space {
					strings.write_byte(&sb, ' ')
					prev_was_space = true
				}
			}
			i += 1
			run_start = i
			continue
		}
		if c == '<' {
			if i > run_start {
				strings.write_string(&sb, html[run_start:i])
				prev_was_space = false
			}
			in_tag = true
			i += 1
			continue
		}
		if c == '&' {
			if i > run_start {
				strings.write_string(&sb, html[run_start:i])
				prev_was_space = false
			}
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
					prev_was_space = false
					i += semi + 1
					run_start = i
					continue
				}
			}
			strings.write_byte(&sb, '&')
			prev_was_space = false
			i += 1
			run_start = i
			continue
		}
		if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
			if i > run_start {
				strings.write_string(&sb, html[run_start:i])
				prev_was_space = false
			}
			if !prev_was_space {
				strings.write_byte(&sb, ' ')
				prev_was_space = true
			}
			i += 1
			run_start = i
			continue
		}
		i += 1
	}
	if i > run_start && !in_tag {
		strings.write_string(&sb, html[run_start:i])
	}

	result := strings.to_string(sb)
	if len(result) > 0 && result[len(result) - 1] == ' ' {
		result = result[:len(result) - 1]
	}
	return result
}
