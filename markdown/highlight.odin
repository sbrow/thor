package markdown

import ts "../treesitter"

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
	for i in 0 ..< ts.node_child_count(root) {
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

write_span_open :: proc(b: ^strings.Builder, buf: ^[128]u8, name: string) {
	pos := 0

	prefix := "<span class=\""
	for i in 0 ..< len(prefix) {
		buf[pos] = prefix[i]
		pos += 1
	}

	first := true
	for i in 0 ..< len(name) {
		if name[i] == '.' {
			if !first {buf[pos] = ' '; pos += 1}
			first = false
			buf[pos] = 'h'; buf[pos + 1] = 'l'; buf[pos + 2] = '-'; pos += 3
			for j in 0 ..< i {
				buf[pos] = '-' if name[j] == '.' else name[j]
				pos += 1
			}
		}
	}
	if !first {buf[pos] = ' '; pos += 1}
	buf[pos] = 'h'; buf[pos + 1] = 'l'; buf[pos + 2] = '-'; pos += 3
	for j in 0 ..< len(name) {
		buf[pos] = '-' if name[j] == '.' else name[j]
		pos += 1
	}
	buf[pos] = '"'; pos += 1
	buf[pos] = '>'; pos += 1

	strings.write_string(b, string(buf[:pos]))
}

write_escaped :: proc(b: ^strings.Builder, s: string) {
	start := 0
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&':
			if i > start do strings.write_string(b, s[start:i])
			strings.write_string(b, "&amp;")
			start = i + 1
		case '<':
			if i > start do strings.write_string(b, s[start:i])
			strings.write_string(b, "&lt;")
			start = i + 1
		case '>':
			if i > start do strings.write_string(b, s[start:i])
			strings.write_string(b, "&gt;")
			start = i + 1
		case '"':
			if i > start do strings.write_string(b, s[start:i])
			strings.write_string(b, "&quot;")
			start = i + 1
		}
	}
	if start == 0 {
		strings.write_string(b, s)
	} else if start < len(s) {
		strings.write_string(b, s[start:])
	}
}

unescape_html :: proc(s: string) -> string {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	start := 0
	for i in 0 ..< len(s) {
		if s[i] != '&' do continue
		semi := strings.index(s[i:], ";")
		if semi < 0 do break
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
			log.warnf(
				"highlight: syntax errors in %s code block at line %d (%s)",
				lang,
				line,
				file_path,
			)
		} else {
			log.warnf("highlight: syntax errors in %s code block (%s)", lang, file_path)
		}
	}

	cursor := gc.cursor
	if cursor == nil {
		return code
	}

	ts.query_cursor_exec(cursor, gc.query, root)

	captures := make([dynamic]Capture, 0, 64, context.temp_allocator)
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
		append(
			&captures,
			Capture {
				start = ts.node_start_byte(cap.node),
				end = ts.node_end_byte(cap.node),
				name = name,
			},
		)
	}

	if len(captures) == 0 {
		return code
	}

	sb := strings.builder_make_len(len(code) * 2)

	last_pos: u32 = 0
	stack := make([dynamic]Capture, 0, 16, context.temp_allocator)
	defer delete(stack)

	buf: [128]u8

	for cap in captures {
		for len(stack) > 0 {
			top := stack[len(stack) - 1]
			if top.end <= cap.start {
				if top.end > last_pos {
					write_escaped(&sb, raw_code[last_pos:top.end])
				}
				strings.write_string(&sb, "</span>")
				last_pos = top.end
				pop(&stack)
			} else {
				break
			}
		}

		if cap.start > last_pos {
			write_escaped(&sb, raw_code[last_pos:cap.start])
			last_pos = cap.start
		}

		write_span_open(&sb, &buf, cap.name)
		append(&stack, cap)
	}

	for len(stack) > 0 {
		top := pop(&stack)
		if top.end > last_pos {
			write_escaped(&sb, raw_code[last_pos:top.end])
		}
		strings.write_string(&sb, "</span>")
		last_pos = top.end
	}

	if int(last_pos) < len(raw_code) {
		write_escaped(&sb, raw_code[last_pos:])
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
		fmt.sbprintf(&sb, `<pre><code class="language-%s">%s</code></pre>`, lang, highlighted)

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
