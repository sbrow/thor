package main

import "core:c"

GRAPHS_PATH: string = "/home/spencer/.config/helix/runtime/grammars"
QUERIES_PATH: string = "/nix/store/n9da8d007ygbgsx983jr3ar3wb1fsh6q-helix-25.07.1/lib/runtime/queries"

TSLanguage :: distinct rawptr
TSParser :: distinct rawptr
TSTree :: distinct rawptr
TSQuery :: distinct rawptr
TSQueryCursor :: distinct rawptr

TSPoint :: struct {
	row:    u32,
	column: u32,
}

TSNode :: struct {
	ctx:   [4]u32,
	id:    rawptr,
	tree:  rawptr,
}

TSQueryCapture :: struct {
	node:  TSNode,
	index: u32,
	_:     u32,
}

TSQueryMatch :: struct {
	id:            u32,
	pattern_index: u16,
	capture_count: u16,
	captures:      [^]TSQueryCapture,
}

TSQueryError :: enum c.int {
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

foreign lib {
	ts_parser_new :: proc() -> TSParser ---
	ts_parser_delete :: proc(self: TSParser) ---
	ts_parser_set_language :: proc(self: TSParser, language: TSLanguage) -> bool ---
	ts_parser_parse_string :: proc(
		self: TSParser,
		old_tree: TSTree,
		string: cstring,
		length: u32,
	) -> TSTree ---
}

foreign lib {
	ts_tree_root_node :: proc(self: TSTree) -> TSNode ---
	ts_tree_delete :: proc(self: TSTree) ---
}

foreign lib {
	ts_node_start_byte :: proc(self: TSNode) -> u32 ---
	ts_node_end_byte :: proc(self: TSNode) -> u32 ---
	ts_node_has_error :: proc(self: TSNode) -> bool ---
	ts_node_is_error :: proc(self: TSNode) -> bool ---
	ts_node_child_count :: proc(self: TSNode) -> u32 ---
	ts_node_child :: proc(self: TSNode, child_index: u32) -> TSNode ---
	ts_node_named_child_count :: proc(self: TSNode) -> u32 ---
	ts_node_named_child :: proc(self: TSNode, child_index: u32) -> TSNode ---
	ts_node_start_point :: proc(self: TSNode) -> TSPoint ---
	ts_node_type :: proc(self: TSNode) -> cstring ---
	ts_node_parent :: proc(self: TSNode) -> TSNode ---
}

foreign lib {
	ts_query_new :: proc(
		language: TSLanguage,
		source: cstring,
		source_len: u32,
		error_offset: ^u32,
		error_type: ^TSQueryError,
	) -> TSQuery ---
	ts_query_delete :: proc(self: TSQuery) ---
	ts_query_capture_name_for_id :: proc(
		self: TSQuery,
		index: u32,
		length: ^u32,
	) -> cstring ---
}

foreign lib {
	ts_query_cursor_new :: proc() -> TSQueryCursor ---
	ts_query_cursor_delete :: proc(self: TSQueryCursor) ---
	ts_query_cursor_exec :: proc(
		self: TSQueryCursor,
		query: TSQuery,
		node: TSNode,
	) ---
	ts_query_cursor_next_capture :: proc(
		self: TSQueryCursor,
		match: ^TSQueryMatch,
		capture_index: ^u32,
	) -> bool ---
}

foreign libdl {
	dlopen :: proc(filename: cstring, flags: c.int) -> rawptr ---
	dlsym :: proc(handle: rawptr, symbol: cstring) -> rawptr ---
	dlclose :: proc(handle: rawptr) -> c.int ---
}

foreign html_grammar {
	tree_sitter_html :: proc() -> TSLanguage ---
}

foreign css_grammar {
	tree_sitter_css :: proc() -> TSLanguage ---
}
