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
	sb := strings.builder_make()
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
		entity := s[i : i + semi + 1]
		replacement := ""
		switch entity {
		case "&amp;":  replacement = "&"
		case "&lt;":   replacement = "<"
		case "&gt;":   replacement = ">"
		case "&quot;": replacement = "\""
		case "&#39;", "&apos;": replacement = "'"
		case: continue
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

// generate_summary produces a plain-text summary of an HTML fragment.
// Blocks (paragraphs, headings, list items) are extracted, their tags
// stripped, entities decoded, and accumulated word-by-word until the
// max_words threshold is crossed — at which point the rest of the
// current block is included before stopping. Mirrors Hugo's default
// summary behavior.
generate_summary :: proc(html: string, max_words: int = 70) -> string {
	separated, _ := strings.replace_all(html, "</p>", "\n\n", context.temp_allocator)
	separated, _ = strings.replace_all(separated, "</h1>", "\n\n")
	separated, _ = strings.replace_all(separated, "</h2>", "\n\n")
	separated, _ = strings.replace_all(separated, "</h3>", "\n\n")
	separated,_ = strings.replace_all(separated, "</h4>", "\n\n")
	separated, _ = strings.replace_all(separated, "</h5>", "\n\n")
	separated, _ = strings.replace_all(separated, "</h6>", "\n\n")
	separated, _ = strings.replace_all(separated, "</li>", "\n\n")
	separated, _ = strings.replace_all(separated, "</blockquote>", "\n\n")

	stripped := strip_html_tags(separated, context.temp_allocator)
	plain := unescape_html(stripped)

	blocks := strings.split(plain, "\n\n", allocator = context.temp_allocator)
	defer delete(blocks)

	sb := strings.builder_make(context.temp_allocator)
	defer strings.builder_destroy(&sb)

	word_count := 0
	first := true
	for raw_block in blocks {
		block := strings.trim_space(raw_block)
		if len(block) == 0 {
			continue
		}

		// Collapse internal whitespace to single spaces.
		block_sb := strings.builder_make(context.temp_allocator)
		has_content := false
		in_space := true
		for c in block {
			if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
				in_space = true
			} else {
				if in_space && has_content {
					strings.write_byte(&block_sb, ' ')
				}
				strings.write_rune(&block_sb, c)
				in_space = false
				has_content = true
			}
		}
		collapsed := strings.to_string(block_sb)
		words := strings.split(collapsed, " ", allocator = context.temp_allocator)

		if !first && word_count > 0 {
			strings.write_byte(&sb, ' ')
		}
		strings.write_string(&sb, collapsed)
		word_count += len(words)
		first = false

		delete(words)

		if word_count >= max_words {
			break
		}
	}

	return strings.to_string(sb)
}
