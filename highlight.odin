package main

import ts "treesitter"

import "core:fmt"
import "core:log"
import "core:strings"

Capture :: struct {
	start: u32,
	end:   u32,
	name:  string,
}

find_first_error_line :: proc(root: ts.Node) -> int {
	if ts.node_is_error(root) {
		return int(ts.node_start_point(root).row) + 1
	}
	for i in 0..<ts.node_child_count(root) {
		child := ts.node_child(root, u32(i))
		if ts.node_has_error(child) {
			line := find_first_error_line(child)
			if line > 0 {
				return line
			}
		}
	}
	return 0
}

capture_name_to_css :: proc(name: string) -> string {
	sb := strings.builder_make()
	seg := strings.builder_make()
	first := true
	for i in 0..<len(name) {
		if name[i] == '.' {
			if !first do strings.write_byte(&sb, ' ')
			first = false
			strings.write_string(&sb, "hl-")
			strings.write_string(&sb, strings.to_string(seg))
			strings.write_byte(&seg, '-')
		} else {
			strings.write_byte(&seg, name[i])
		}
	}
	if !first do strings.write_byte(&sb, ' ')
	strings.write_string(&sb, "hl-")
	strings.write_string(&sb, strings.to_string(seg))
	return strings.to_string(sb)
}

escape_html :: proc(s: string) -> string {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	start := 0
	for i in 0..<len(s) {
		switch s[i] {
		case '&':
			if i > start do strings.write_string(&sb, s[start:i])
			strings.write_string(&sb, "&amp;")
			start = i + 1
		case '<':
			if i > start do strings.write_string(&sb, s[start:i])
			strings.write_string(&sb, "&lt;")
			start = i + 1
		case '>':
			if i > start do strings.write_string(&sb, s[start:i])
			strings.write_string(&sb, "&gt;")
			start = i + 1
		case '"':
			if i > start do strings.write_string(&sb, s[start:i])
			strings.write_string(&sb, "&quot;")
			start = i + 1
		}
	}
	if start == 0 do return s
	if start < len(s) do strings.write_string(&sb, s[start:])
	return strings.to_string(sb)
}

unescape_html :: proc(s: string) -> string {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	start := 0
	for i in 0..<len(s) {
		if s[i] != '&' do continue
		semi := strings.index(s[i:], ";")
		if semi < 0 do break
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
		if i > start do strings.write_string(&sb, s[start:i])
		strings.write_string(&sb, replacement)
		start = i + semi + 1
	}
	if start == 0 do return s
	if start < len(s) do strings.write_string(&sb, s[start:])
	return strings.to_string(sb)
}

highlight_block :: proc(code: string, lang: string, file_path: string) -> string {
	gc := ts.load_grammar(lang)
	if gc == nil {
		return code
	}

	raw_code := unescape_html(code)
	raw_c := strings.clone_to_cstring(raw_code)
	defer delete(raw_c)

	tree := ts.parser_parse_string(gc.parser, nil, raw_c, u32(len(raw_code)))
	if tree == nil {
		return code
	}
	defer ts.tree_delete(tree)

	root := ts.tree_root_node(tree)

	if ts.node_has_error(root) {
		line := find_first_error_line(root)
		if line > 0 {
			log.warnf("highlight: syntax errors in %s code block at line %d (%s)", lang, line, file_path)
		} else {
			log.warnf("highlight: syntax errors in %s code block (%s)", lang, file_path)
		}
	}

	cursor := ts.query_cursor_new()
	if cursor == nil {
		return code
	}
	defer ts.query_cursor_delete(cursor)

	ts.query_cursor_exec(cursor, gc.query, root)

	captures: [dynamic]Capture
	defer delete(captures)

	match: ts.Query_Match
	capture_idx: u32
	for ts.query_cursor_next_capture(cursor, &match, &capture_idx) {
		if capture_idx >= u32(match.capture_count) {
			continue
		}
		cap := match.captures[capture_idx]
		name_len: u32
		name_c := ts.query_capture_name_for_id(gc.query, cap.index, &name_len)
		if name_c == nil {
			continue
		}
		name_full := string(name_c)
		name := name_full
		if len(name_full) > int(name_len) {
			name = name_full[:int(name_len)]
		}
		append(&captures, Capture{
			start = ts.node_start_byte(cap.node),
			end = ts.node_end_byte(cap.node),
			name = name,
		})
	}

	if len(captures) == 0 {
		return code
	}

	sb := strings.builder_make()

	last_pos: u32 = 0
	stack: [dynamic]Capture
	defer delete(stack)

	for cap in captures {
		for len(stack) > 0 {
			top := stack[len(stack) - 1]
			if top.end <= cap.start {
				if top.end > last_pos {
					strings.write_string(&sb, escape_html(raw_code[last_pos:top.end]))
				}
				strings.write_string(&sb, "</span>")
				last_pos = top.end
				pop(&stack)
			} else {
				break
			}
		}

		if cap.start > last_pos {
			strings.write_string(&sb, escape_html(raw_code[last_pos:cap.start]))
			last_pos = cap.start
		}

		css_class := capture_name_to_css(cap.name)
		strings.write_string(&sb, fmt.tprintf("<span class=\"%s\">", css_class))
		append(&stack, cap)
	}

	for len(stack) > 0 {
		top := pop(&stack)
		if top.end > last_pos {
			strings.write_string(&sb, escape_html(raw_code[last_pos:top.end]))
		}
		strings.write_string(&sb, "</span>")
		last_pos = top.end
	}

	if int(last_pos) < len(raw_code) {
		strings.write_string(&sb, escape_html(raw_code[last_pos:]))
	}

	return strings.to_string(sb)
}

highlight_code :: proc(html: string, file_path: string) -> string {
	PREFIX :: `<pre><code class="language-`
	CODE_END :: `</code></pre>`

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	pos := 0
	found := false

	for {
		rel := strings.index(html[pos:], PREFIX)
		if rel < 0 {
			break
		}
		found = true
		idx := pos + rel

		if idx > pos {
			strings.write_string(&sb, html[pos:idx])
		}

		lang_start := idx + len(PREFIX)
		lang_end_rel := strings.index(html[lang_start:], `"`)
		if lang_end_rel < 0 {
			break
		}
		lang_end := lang_start + lang_end_rel
		lang := html[lang_start:lang_end]

		code_start := lang_end + 1
		if code_start < len(html) && html[code_start] == '>' {
			code_start += 1
		} else {
			pos = lang_end
			continue
		}

		end_rel := strings.index(html[code_start:], CODE_END)
		if end_rel < 0 {
			break
		}
		end_idx := code_start + end_rel

		code := html[code_start:end_idx]
		highlighted := highlight_block(code, lang, file_path)
		strings.write_string(&sb, fmt.tprintf(`<pre><code class="language-%s">%s</code></pre>`, lang, highlighted))

		pos = end_idx + len(CODE_END)
	}

	if pos < len(html) && found {
		strings.write_string(&sb, html[pos:])
	}

	if !found {
		return html
	}
	return strings.to_string(sb)
}
