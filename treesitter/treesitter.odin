package treesitter

import "core:c"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

GRAPHS_PATH: string = "/home/spencer/.config/helix/runtime/grammars"
QUERIES_PATH: string = "/nix/store/n9da8d007ygbgsx983jr3ar3wb1fsh6q-helix-25.07.1/lib/runtime/queries"

Language :: distinct rawptr
Parser :: distinct rawptr
Tree :: distinct rawptr
Query :: distinct rawptr
Query_Cursor :: distinct rawptr

Point :: struct {
	row:    u32,
	column: u32,
}

Node :: struct {
	ctx:   [4]u32,
	id:    rawptr,
	tree:  rawptr,
}

Query_Capture :: struct {
	node:  Node,
	index: u32,
	_:     u32,
}

Query_Match :: struct {
	id:            u32,
	pattern_index: u16,
	capture_count: u16,
	captures:      [^]Query_Capture,
}

Query_Error :: enum c.int {
	None     = 0,
	Syntax,
	NodeType,
	Field,
	Capture,
	Structure,
	Language,
}

RTLD_LAZY :: c.int(1)

foreign import lib "system:tree-sitter"
foreign import libdl "system:dl"
foreign import html_grammar "system:tree-sitter-html"
foreign import css_grammar "system:tree-sitter-css"

@(link_prefix="ts_")
foreign lib {
	parser_new :: proc() -> Parser ---
	parser_delete :: proc(self: Parser) ---
	parser_set_language :: proc(self: Parser, language: Language) -> bool ---
	parser_parse_string :: proc(
		self: Parser,
		old_tree: Tree,
		string: cstring,
		length: u32,
	) -> Tree ---
}

@(link_prefix="ts_")
foreign lib {
	 tree_root_node :: proc(self: Tree) -> Node ---
	 tree_delete :: proc(self: Tree) ---
}

@(link_prefix="ts_")
foreign lib {
	 node_start_byte :: proc(self: Node) -> u32 ---
	 node_end_byte :: proc(self: Node) -> u32 ---
	 node_has_error :: proc(self: Node) -> bool ---
	 node_is_error :: proc(self: Node) -> bool ---
	 node_child_count :: proc(self: Node) -> u32 ---
	 node_child :: proc(self: Node, child_index: u32) -> Node ---
	 node_named_child_count :: proc(self: Node) -> u32 ---
	 node_named_child :: proc(self: Node, child_index: u32) -> Node ---
	 node_start_point :: proc(self: Node) -> Point ---
	 node_type :: proc(self: Node) -> cstring ---
	 node_parent :: proc(self: Node) -> Node ---
}

@(link_prefix="ts_")
foreign lib {
	 query_new :: proc(
		language: Language,
		source: cstring,
		source_len: u32,
		error_offset: ^u32,
		error_type: ^Query_Error,
	) -> Query ---
	query_delete :: proc(self: Query) ---
	query_capture_name_for_id :: proc(
		self: Query,
		index: u32,
		length: ^u32,
	) -> cstring ---
}

@(link_prefix="ts_")
foreign lib {
	query_cursor_new :: proc() -> Query_Cursor ---
	query_cursor_delete :: proc(self: Query_Cursor) ---
	query_cursor_exec :: proc(
		self: Query_Cursor,
		query: Query,
		node: Node,
	) ---
	query_cursor_next_capture :: proc(
		self: Query_Cursor,
		match: ^Query_Match,
		capture_index: ^u32,
	) -> bool ---
}

foreign libdl {
	dlopen :: proc(filename: cstring, flags: c.int) -> rawptr ---
	dlsym :: proc(handle: rawptr, symbol: cstring) -> rawptr ---
	dlclose :: proc(handle: rawptr) -> c.int ---
}

foreign html_grammar {
	tree_sitter_html :: proc() -> Language ---
}

foreign css_grammar {
	tree_sitter_css :: proc() -> Language ---
}

Grammar_Cache :: struct {
	language:     Language,
	parser:       Parser,
	query:        Query,
	query_failed: bool,
}

Get_Language_Proc :: #type proc() -> Language

grammar_cache: map[string]^Grammar_Cache

builtin_language :: proc(lang: string) -> (language: Language, ok: bool) {
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

	language: Language

	if builtin, ok := builtin_language(lang); ok {
		language = builtin
	} else {
		if GRAPHS_PATH == "" {
			log.warnf("treesitter: no grammars path set, skipping %s", lang)
			return nil
		}

		so_path := fmt.tprintf("%s/%s.so", GRAPHS_PATH, lang)
		so_c := strings.clone_to_cstring(so_path)
		defer delete(so_c)
		handle := dlopen(so_c, RTLD_LAZY)
		if handle == nil {
			log.warnf("treesitter: cannot load grammar %s (%s)", lang, so_path)
			return nil
		}

		sym_name := fmt.tprintf("tree_sitter_%s", lang)
		sym_c := strings.clone_to_cstring(sym_name)
		defer delete(sym_c)
		sym := dlsym(handle, sym_c)
		if sym == nil {
			log.errorf("treesitter: cannot find symbol %s in %s", sym_name, so_path)
			return nil
		}
		get_language := transmute(Get_Language_Proc)(sym)
		language = get_language()
	}

	parser := parser_new()
	if parser == nil {
		log.errorf("treesitter: cannot create parser for %s", lang)
		return nil
	}
	if !parser_set_language(parser, language) {
		log.errorf("treesitter: ABI mismatch for %s grammar", lang)
		parser_delete(parser)
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
		log.warnf("treesitter: no queries path set, skipping %s", lang)
		gc.query_failed = true
		return nil
	}

	query_path := fmt.tprintf("%s/%s/highlights.scm", QUERIES_PATH, lang)
	query_src, err := os.read_entire_file_from_path(query_path, context.allocator)
	if err != nil {
		log.warnf("treesitter: cannot load query %s", query_path)
		gc.query_failed = true
		return nil
	}
	query_str := string(query_src)
	query_c := strings.clone_to_cstring(query_str)
	defer delete(query_c)

	err_offset: u32
	err_type: Query_Error
	query := query_new(
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
		log.errorf("treesitter: %s query failed: %s", lang, cause)

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
