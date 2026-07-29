package treesitter

import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"

grammar_dir: string
query_dir: string

HTML_HIGHLIGHTS :: #load(#directory + "queries/html/highlights.scm", string)
CSS_HIGHLIGHTS :: #load(#directory + "queries/css/highlights.scm", string)

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
	ctx:  [4]u32,
	id:   rawptr,
	tree: rawptr,
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
	None = 0,
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

@(link_prefix = "ts_")
foreign lib {
	parser_new :: proc() -> Parser ---
	parser_delete :: proc(self: Parser) ---
	parser_set_language :: proc(self: Parser, language: Language) -> bool ---
	parser_parse_string :: proc(self: Parser, old_tree: Tree, string: cstring, length: u32) -> Tree ---
}

@(link_prefix = "ts_")
foreign lib {
	tree_root_node :: proc(self: Tree) -> Node ---
	tree_delete :: proc(self: Tree) ---
}

@(link_prefix = "ts_")
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

@(link_prefix = "ts_")
foreign lib {
	query_new :: proc(language: Language, source: cstring, source_len: u32, error_offset: ^u32, error_type: ^Query_Error) -> Query ---
	query_delete :: proc(self: Query) ---
	query_capture_name_for_id :: proc(self: Query, index: u32, length: ^u32) -> cstring ---
}

@(link_prefix = "ts_")
foreign lib {
	query_cursor_new :: proc() -> Query_Cursor ---
	query_cursor_delete :: proc(self: Query_Cursor) ---
	query_cursor_exec :: proc(self: Query_Cursor, query: Query, node: Node) ---
	query_cursor_next_capture :: proc(self: Query_Cursor, match: ^Query_Match, capture_index: ^u32) -> bool ---
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
	cursor:       Query_Cursor,
	query_failed: bool,
}

Get_Language_Proc :: #type proc() -> Language

SPALL :: #config(SPALL, false)

grammar_store: Grammar_Store
cache_mutex: sync.Mutex

Grammar_Store :: struct {
	cache:     map[string]^Grammar_Cache,
	allocator: mem.Allocator,
}

init_persistent :: proc() {
	grammar_store.allocator = context.allocator
	grammar_store.cache = make(map[string]^Grammar_Cache, grammar_store.allocator)
}

when SPALL {
	_thread_init: proc() = nil
	_thread_cleanup: proc() = nil

	set_thread_callbacks :: proc(init: proc() = nil, cleanup: proc() = nil) {
		_thread_init = init
		_thread_cleanup = cleanup
	}
}

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

// load_query returns the highlight query source for a language. Builtin
// languages (html/css) are baked into the binary via `#load`; all others are
// read from the runtime `query_dir`. `path` is the on-disk location for
// diagnostics ("(builtin)" for embedded queries). Mirrors `ensure_parser`.
load_query :: proc(lang: string) -> (src: string, path: string, ok: bool) {
	switch lang {
	case "html":
		return HTML_HIGHLIGHTS, "(builtin)", true
	case "css":
		return CSS_HIGHLIGHTS, "(builtin)", true
	}
	if query_dir == "" {
		log.warnf("treesitter: no query path set, skipping %s", lang)
		return "", "", false
	}
	path = fmt.tprintf("%s/%s/highlights.scm", query_dir, lang)
	raw, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		log.warnf("treesitter: cannot load query %s", path)
		return "", "", false
	}
	return string(raw), path, true
}

load_language :: proc(lang: string) -> (language: Language, ok: bool) {
	if builtin, bok := builtin_language(lang); bok {
		language = builtin
		ok = true
		return
	}
	if grammar_dir == "" {
		log.warnf("treesitter: no grammar path set, skipping %s", lang)
		return
	}
	so_path := fmt.caprintf("%s/%s.so", grammar_dir, lang, allocator = context.temp_allocator)
	handle := dlopen(so_path, RTLD_LAZY)
	if handle == nil {
		log.warnf("treesitter: cannot load grammar %s (%s)", lang, so_path)
		return
	}
	sym_name := fmt.caprintf("tree_sitter_%s", lang, allocator = context.temp_allocator)
	sym := dlsym(handle, sym_name)
	if sym == nil {
		log.errorf("treesitter: cannot find symbol %s in %s", sym_name, so_path)
		return
	}
	get_language := transmute(Get_Language_Proc)(sym)
	language = get_language()
	ok = true
	return
}

ensure_parser :: proc(lang: string) -> ^Grammar_Cache {
	if cached, ok := grammar_store.cache[lang]; ok {
		return cached
	}

	grammar_store.cache[lang] = nil

	language, ok := load_language(lang)
	if !ok {
		return nil
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

	gc := new(Grammar_Cache, grammar_store.allocator)
	gc.language = language
	gc.parser = parser
	grammar_store.cache[lang] = gc
	return gc
}

compile_query :: proc(
	lang: string,
	language: Language,
) -> (
	query: Query,
	cursor: Query_Cursor,
	ok: bool,
) {
	query_src, query_path, qok := load_query(lang)
	if !qok {
		return
	}
	query_c := strings.clone_to_cstring(query_src, context.temp_allocator)

	err_offset: u32
	err_type: Query_Error
	query = query_new(language, query_c, u32(len(query_src)), &err_offset, &err_type)
	if query == nil {
		tok := extract_query_token(transmute([]byte)query_src, err_offset)
		cause := fmt.tprintf("query error at byte %d (type %v)", err_offset, err_type)
		#partial switch err_type {
		case .NodeType:
			if tok != "" {
				cause = fmt.tprintf(
					"query references unknown node type '%s' (byte %d); the grammar (.so) and query (.scm) are likely from different tree-sitter-%s versions",
					tok,
					err_offset,
					lang,
				)
			} else {
				cause = fmt.tprintf(
					"query references an unknown node type at byte %d; the grammar (.so) and query (.scm) are likely from different tree-sitter-%s versions",
					err_offset,
					lang,
				)
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
			so_path := fmt.tprintf("%s/%s.so", grammar_dir, lang)
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

		return
	}

	cursor = query_cursor_new()
	ok = true
	return
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

	query, cursor, ok := compile_query(lang, gc.language)
	if !ok {
		gc.query_failed = true
		return nil
	}

	gc.query = query
	gc.cursor = cursor
	return gc
}

preload_grammar :: proc(lang: string) -> ^Grammar_Cache {
	language, ok := load_language(lang)
	if !ok {
		return nil
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

	gc := new(Grammar_Cache, grammar_store.allocator)
	gc.language = language
	gc.parser = parser

	query, cursor, qok := compile_query(lang, language)
	if !qok {
		gc.query_failed = true
		return gc
	}

	gc.query = query
	gc.cursor = cursor
	return gc
}

preload_grammars :: proc(languages: []string) {
	if len(languages) == 0 {
		return
	}

	// Filter out already-loaded languages (watch mode reuse)
	to_load := make([dynamic]string, 0, len(languages), context.temp_allocator)
	for lang in languages {
		if cached, ok := grammar_store.cache[lang]; ok && cached != nil {
			continue
		}
		if _, bok := builtin_language(lang); bok {
			continue
		}
		append(&to_load, lang)
	}

	if len(to_load) == 0 {
		return
	}

	threads := make([]^thread.Thread, len(to_load), context.temp_allocator)
	for i in 0 ..< len(to_load) {
		threads[i] = thread.create_and_start_with_poly_data(to_load[i], grammar_worker)
	}
	for t in threads {
		thread.join(t)
		thread.destroy(t)
	}
}

grammar_worker :: proc(lang: string) {
	when SPALL {
		if _thread_init != nil {
			_thread_init()
		}
		defer if _thread_cleanup != nil {
			_thread_cleanup()
		}
	}

	gc := preload_grammar(lang)
	if gc != nil {
		sync.mutex_lock(&cache_mutex)
		grammar_store.cache[lang] = gc
		sync.mutex_unlock(&cache_mutex)
	}
}

extract_query_token :: proc(src: []byte, offset: u32) -> string {
	end := offset
	for int(end) < len(src) {
		c := src[end]
		is_ident :=
			(c >= 'A' && c <= 'Z') ||
			(c >= 'a' && c <= 'z') ||
			(c >= '0' && c <= '9') ||
			c == '_' ||
			c == '-' ||
			c == '.'
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
