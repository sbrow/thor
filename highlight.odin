package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

Grammar_Cache :: struct {
	language:     TSLanguage,
	parser:       TSParser,
	query:        TSQuery,
	query_failed: bool,
}

Get_Language_Proc :: #type proc() -> TSLanguage

grammar_cache: map[string]^Grammar_Cache

builtin_language :: proc(lang: string) -> (language: TSLanguage, ok: bool) {
	switch lang {
	case "html":
		language = tree_sitter_html()
		ok = true
	case "css":
		language = tree_sitter_css()
		ok = true
	}
	return
}

ensure_parser :: proc(lang: string) -> ^Grammar_Cache {
	if grammar_cache == nil {
		grammar_cache = make(map[string]^Grammar_Cache)
	}
	if cached, ok := grammar_cache[lang]; ok {
		return cached
	}

	grammar_cache[lang] = nil

	language: TSLanguage

	if builtin, ok := builtin_language(lang); ok {
		language = builtin
	} else {
		if GRAPHS_PATH == "" {
			log.warnf("highlight: no grammars path set, skipping %s", lang)
			return nil
		}

		so_path := fmt.tprintf("%s/%s.so", GRAPHS_PATH, lang)
		so_c := strings.clone_to_cstring(so_path)
		defer delete(so_c)
		handle := dlopen(so_c, RTLD_LAZY)
		if handle == nil {
			log.warnf("highlight: cannot load grammar %s (%s)", lang, so_path)
			return nil
		}

		sym_name := fmt.tprintf("tree_sitter_%s", lang)
		sym_c := strings.clone_to_cstring(sym_name)
		defer delete(sym_c)
		sym := dlsym(handle, sym_c)
		if sym == nil {
			log.errorf("highlight: cannot find symbol %s in %s", sym_name, so_path)
			return nil
		}
		get_language := transmute(Get_Language_Proc)(sym)
		language = get_language()
	}

	parser := ts_parser_new()
	if parser == nil {
		log.errorf("highlight: cannot create parser for %s", lang)
		return nil
	}
	if !ts_parser_set_language(parser, language) {
		log.errorf("highlight: ABI mismatch for %s grammar", lang)
		ts_parser_delete(parser)
		return nil
	}

	gc := new(Grammar_Cache)
	gc.language = language
	gc.parser = parser
	grammar_cache[lang] = gc
	return gc
}

load_grammar :: proc(lang: string) -> ^Grammar_Cache {
	gc := ensure_parser(lang)
	if gc == nil {
		return nil
	}
	if gc.query != nil {
		return gc
	}
	if gc.query_failed {
		return nil
	}

	if QUERIES_PATH == "" {
		log.warnf("highlight: no queries path set, skipping %s", lang)
		gc.query_failed = true
		return nil
	}

	query_path := fmt.tprintf("%s/%s/highlights.scm", QUERIES_PATH, lang)
	query_src, err := os.read_entire_file_from_path(query_path, context.allocator)
	if err != nil {
		log.warnf("highlight: cannot load query %s", query_path)
		gc.query_failed = true
		return nil
	}
	query_str := string(query_src)
	query_c := strings.clone_to_cstring(query_str)
	defer delete(query_c)

	err_offset: u32
	err_type: TSQueryError
	query := ts_query_new(
		gc.language,
		query_c,
		u32(len(query_src)),
		&err_offset,
		&err_type,
	)
	if query == nil {
		tok := extract_query_token(query_src, err_offset)
		cause := fmt.tprintf("query error at byte %d (type %v)", err_offset, err_type)
		#partial switch err_type {
		case .NodeType:
			if tok != "" {
				cause = fmt.tprintf("query references unknown node type '%s' (byte %d); the grammar (.so) and query (.scm) are likely from different tree-sitter-%s versions", tok, err_offset, lang)
			} else {
				cause = fmt.tprintf("query references an unknown node type at byte %d; the grammar (.so) and query (.scm) are likely from different tree-sitter-%s versions", err_offset, lang)
			}
		case .Field:
			cause = fmt.tprintf("query references unknown field '%s' at byte %d", tok, err_offset)
		case .Capture:
			cause = fmt.tprintf("query uses an invalid capture '%s' at byte %d", tok, err_offset)
		case .Syntax:
			cause = fmt.tprintf("query has a syntax error at byte %d", err_offset)
		case .Structure:
			cause = fmt.tprintf("query has an illegal pattern structure at byte %d", err_offset)
		case .Language:
			cause = "grammar language is null (broken grammar .so)"
		}
		log.errorf("highlight: %s query failed: %s", lang, cause)

		_, is_builtin := builtin_language(lang)
		if !is_builtin {
			so_path := fmt.tprintf("%s/%s.so", GRAPHS_PATH, lang)
			gram_v := helix_version_from_path(so_path)
			query_v := helix_version_from_path(query_path)
			gram_note := "(version unknown)"
			if gram_v != "" do gram_note = fmt.tprintf("helix %s", gram_v)
			query_note := "(version unknown)"
			if query_v != "" do query_note = fmt.tprintf("helix %s", query_v)
			log.errorf("  grammar: %s [%s]", so_path, gram_note)
			log.errorf("  query:   %s [%s]", query_path, query_note)
			if gram_v != "" && query_v != "" && gram_v != query_v {
				log.errorf("  >> helix VERSION MISMATCH: grammar %s vs query %s", gram_v, query_v)
			}
		}

		gc.query_failed = true
		return nil
	}

	gc.query = query
	return gc
}

extract_query_token :: proc(src: []byte, offset: u32) -> string {
	end := offset
	for int(end) < len(src) {
		c := src[end]
		is_ident := (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
			(c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.'
		if !is_ident do break
		end += 1
	}
	if end <= offset do return ""
	return string(src[offset:end])
}

helix_version_from_path :: proc(path: string) -> string {
	tag := "-helix-"
	idx := strings.index(path, tag)
	if idx < 0 do return ""
	start := idx + len(tag)
	end := start
	for end < len(path) {
		c := path[end]
		if !((c >= '0' && c <= '9') || c == '.') do break
		end += 1
	}
	if end <= start do return ""
	return path[start:end]
}

Capture :: struct {
	start: u32,
	end:   u32,
	name:  string,
}

find_first_error_line :: proc(root: TSNode) -> int {
	if ts_node_is_error(root) {
		return int(ts_node_start_point(root).row) + 1
	}
	for i in 0..<ts_node_child_count(root) {
		child := ts_node_child(root, u32(i))
		if ts_node_has_error(child) {
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
	parts: [dynamic]string
	defer delete(parts)
	start := 0
	for i in 0..<len(s) {
		switch s[i] {
		case '&':
			if i > start do append(&parts, s[start:i])
			append(&parts, "&amp;")
			start = i + 1
		case '<':
			if i > start do append(&parts, s[start:i])
			append(&parts, "&lt;")
			start = i + 1
		case '>':
			if i > start do append(&parts, s[start:i])
			append(&parts, "&gt;")
			start = i + 1
		case '"':
			if i > start do append(&parts, s[start:i])
			append(&parts, "&quot;")
			start = i + 1
		}
	}
	if start < len(s) do append(&parts, s[start:])
	if len(parts) == 0 do return s
	return strings.join(parts[:], "")
}

unescape_html :: proc(s: string) -> string {
	parts: [dynamic]string
	defer delete(parts)
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
		if i > start do append(&parts, s[start:i])
		append(&parts, replacement)
		start = i + semi + 1
	}
	if start < len(s) do append(&parts, s[start:])
	if len(parts) == 0 do return s
	return strings.join(parts[:], "")
}

highlight_block :: proc(code: string, lang: string, file_path: string) -> string {
	gc := load_grammar(lang)
	if gc == nil {
		return code
	}

	raw_code := unescape_html(code)
	raw_c := strings.clone_to_cstring(raw_code)
	defer delete(raw_c)

	tree := ts_parser_parse_string(gc.parser, nil, raw_c, u32(len(raw_code)))
	if tree == nil {
		return code
	}
	defer ts_tree_delete(tree)

	root := ts_tree_root_node(tree)

	if ts_node_has_error(root) {
		line := find_first_error_line(root)
		if line > 0 {
			log.warnf("highlight: syntax errors in %s code block at line %d (%s)", lang, line, file_path)
		} else {
			log.warnf("highlight: syntax errors in %s code block (%s)", lang, file_path)
		}
	}

	cursor := ts_query_cursor_new()
	if cursor == nil {
		return code
	}
	defer ts_query_cursor_delete(cursor)

	ts_query_cursor_exec(cursor, gc.query, root)

	captures: [dynamic]Capture
	defer delete(captures)

	match: TSQueryMatch
	capture_idx: u32
	for ts_query_cursor_next_capture(cursor, &match, &capture_idx) {
		if capture_idx >= u32(match.capture_count) {
			continue
		}
		cap := match.captures[capture_idx]
		name_len: u32
		name_c := ts_query_capture_name_for_id(gc.query, cap.index, &name_len)
		if name_c == nil {
			continue
		}
		name_full := string(name_c)
		name := name_full
		if len(name_full) > int(name_len) {
			name = name_full[:int(name_len)]
		}
		append(&captures, Capture{
			start = ts_node_start_byte(cap.node),
			end = ts_node_end_byte(cap.node),
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

	parts: [dynamic]string
	defer delete(parts)
	pos := 0

	for {
		rel := strings.index(html[pos:], PREFIX)
		if rel < 0 {
			break
		}
		idx := pos + rel

		if idx > pos {
			append(&parts, html[pos:idx])
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
		append(&parts, fmt.tprintf(`<pre><code class="language-%s">%s</code></pre>`, lang, highlighted))

		pos = end_idx + len(CODE_END)
	}

	if pos < len(html) {
		append(&parts, html[pos:])
	}

	if len(parts) == 0 {
		return html
	}
	return strings.join(parts[:], "")
}
