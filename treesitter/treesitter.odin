package treesitter

import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import si "core:sys/info"
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

// A Grammar bundles only the immutable, shareable tree-sitter objects for a
// language: `language` (from tree_sitter_x() or a dlopen'd .so) and `query` (the
// compiled highlight query). Both are immutable after construction and safe to
// read from any number of threads. The stateful, single-thread-use objects —
// parser and query cursor — are deliberately NOT stored here; the caller creates
// and owns those (see `open_parser`). See GRAMMAR_CACHE_THREADING.md.
Grammar :: struct {
	language:     Language,
	query:        Query,
	query_failed: bool,
}

Get_Language_Proc :: #type proc() -> Language

SPALL :: #config(SPALL, false)

// registry is the process-lifetime cache of immutable Grammars, keyed by language
// name. It is the library's ONLY shared mutable state; `mu` serializes all access.
// A nil value memoizes "tried and unavailable" so misses don't re-dlopen. Parsers
// live in the caller, so the registry holds nothing single-thread-use.
Grammar_Registry :: struct {
	mu:        sync.Mutex,
	grammars:  map[string]^Grammar,
	allocator: mem.Allocator,
}

registry: Grammar_Registry

// init_persistent is optional — grammar() lazily initializes the registry on first
// use — but callers (main) may call it to bind the cache early. The allocator is
// pinned to the OS heap, NOT context.allocator, so the cache survives any transient
// allocator (per-build arena, per-test tracking) that happens to be live.
init_persistent :: proc() {
	sync.mutex_lock(&registry.mu)
	defer sync.mutex_unlock(&registry.mu)
	ensure_registry()
}

// ensure_registry binds the registry to the heap on first use. Caller must hold mu.
@(private)
ensure_registry :: proc() {
	if registry.grammars == nil {
		registry.allocator = os.heap_allocator()
		registry.grammars = make(map[string]^Grammar, registry.allocator)
	}
}

// grammar returns the immutable Grammar for `lang`, loading it on first use.
// Thread-safe: concurrent callers serialize on `mu`. Returns (nil, false) when the
// grammar cannot be loaded. The returned pointer is immutable — callers may cache
// and read it (its `language`/`query`) without any further locking.
grammar :: proc(lang: string) -> (^Grammar, bool) {
	sync.mutex_lock(&registry.mu)
	defer sync.mutex_unlock(&registry.mu)
	ensure_registry()
	if g, seen := registry.grammars[lang]; seen {
		return g, g != nil
	}
	g := build_grammar(lang)
	registry.grammars[lang] = g
	return g, g != nil
}

// build_grammar loads a language and compiles its highlight query. It touches no
// shared mutable state — only the set-once `registry.allocator` (for the heap
// `new`), read-only globals, and the per-thread temp allocator — so it is safe to
// run OFF the lock and concurrently, provided `ensure_registry` has already run
// (see preload_grammars). Returns nil if the language itself cannot be loaded; a
// grammar whose query is absent/failed is still returned (parsing works,
// highlighting does not).
@(private)
build_grammar :: proc(lang: string) -> ^Grammar {
	language, ok := load_language(lang)
	if !ok {
		return nil
	}
	g := new(Grammar, registry.allocator)
	g.language = language
	if query, qok := compile_query(lang, language); qok {
		g.query = query
	} else {
		g.query_failed = true
	}
	return g
}

// open_parser creates a fresh parser bound to the grammar's language. The CALLER
// owns the returned parser and must free it with parser_delete. This is the seam
// for parser lifetime: today callers open one and reuse it across a batch of
// parses on a single thread (render opens an html+css pair per render_site;
// assets opens one per copy_assets_dir), which is safe because nothing is shared.
// A future pooling or thread-local strategy can be dropped in here without
// touching any call site. Returns nil on failure.
open_parser :: proc(g: ^Grammar) -> Parser {
	if g == nil {
		return nil
	}
	parser := parser_new()
	if parser == nil {
		log.errorf("treesitter: cannot create parser")
		return nil
	}
	if !parser_set_language(parser, g.language) {
		log.errorf("treesitter: ABI mismatch setting parser language")
		parser_delete(parser)
		return nil
	}
	return parser
}

when SPALL {
	_thread_init: proc() = nil
	_thread_cleanup: proc() = nil

	set_thread_callbacks :: proc(init: proc() = nil, cleanup: proc() = nil) {
		_thread_init = init
		_thread_cleanup = cleanup
	}

	// Pool-shaped adapters: the thread pool calls these once per worker thread at
	// startup/shutdown, so each worker's parses land in their own SPALL thread.
	spall_pool_thread_init :: proc(t: ^thread.Thread, data: rawptr) {
		if _thread_init != nil {
			_thread_init()
		}
	}
	spall_pool_thread_fini :: proc(t: ^thread.Thread, data: rawptr) {
		if _thread_cleanup != nil {
			_thread_cleanup()
		}
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
// diagnostics ("(builtin)" for embedded queries). Mirrors `load_language`.
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

compile_query :: proc(lang: string, language: Language) -> (query: Query, ok: bool) {
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
		switch err_type {
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
		case .None:
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

	ok = true
	return
}

// PRELOAD_MAX_WORKERS caps the pool when the CPU count is unknown or absurd.
PRELOAD_MAX_WORKERS :: 4

// Preload_Task is the per-language work item handed to a pool worker.
Preload_Task :: struct {
	lang: string,
}

// preload_worker builds one grammar off the lock (dlopen + query compile — the
// expensive, parallelizable part), then takes `mu` only to publish the finished
// pointer. Publishing nil memoizes a failed load, matching grammar()/build_grammar.
@(private)
preload_worker :: proc(task: thread.Task) {
	pt := cast(^Preload_Task)task.data
	g := build_grammar(pt.lang)
	sync.mutex_lock(&registry.mu)
	registry.grammars[pt.lang] = g
	sync.mutex_unlock(&registry.mu)
}

// preload_grammars warms the registry for the given languages ahead of the render
// loop, so the first page that needs one doesn't pay the load cost inline. The
// expensive per-language work (dlopen + compile_query) runs concurrently on a
// bounded thread pool. Builtins are always available lazily and are skipped.
//
// INVARIANT: preload runs to completion before any concurrent lazy grammar() use
// (render is single-threaded and runs afterward), so the registry is never read
// while workers publish. Workers still take `mu` for the map insert, keeping the
// "registry is only ever mutated under mu" discipline uniform with grammar().
preload_grammars :: proc(languages: []string) {
	// Snapshot (main thread, under mu): pin the registry allocator before any
	// worker reads it, and collect the languages still needing a load. Dedupes
	// against builtins and already-cached grammars (watch-mode reuse).
	sync.mutex_lock(&registry.mu)
	ensure_registry()
	to_load := make([dynamic]string, 0, len(languages), context.temp_allocator)
	for lang in languages {
		if _, bok := builtin_language(lang); bok {
			continue
		}
		if _, seen := registry.grammars[lang]; seen {
			continue
		}
		append(&to_load, lang)
	}
	sync.mutex_unlock(&registry.mu)

	if len(to_load) == 0 {
		return
	}

	// Bind the pool to the logical core count (load is dlopen/CPU-bound), but
	// never more workers than tasks, never fewer than one.
	worker_count: int = ---
	if _, logical, ok := si.cpu_core_count(); ok {
		assert(logical > 0)
		worker_count = min(logical, len(to_load))
	} else {
		worker_count = min(PRELOAD_MAX_WORKERS, len(to_load))
	}

	// Serial fast path: a single worker gains nothing from the pool machinery.
	if worker_count == 1 {
		for lang in to_load {
			g := build_grammar(lang)
			sync.mutex_lock(&registry.mu)
			registry.grammars[lang] = g
			sync.mutex_unlock(&registry.mu)
		}
		return
	}

	// The pool appends to its own `tasks_done` from worker threads, so its
	// bookkeeping allocator MUST be thread-safe — use the heap, not the (possibly
	// arena) context allocator that is live during a build.
	pool: thread.Pool
	init_proc: thread.Thread_Init_Proc = nil
	fini_proc: thread.Thread_Init_Proc = nil
	when SPALL {
		init_proc = spall_pool_thread_init
		fini_proc = spall_pool_thread_fini
	}
	thread.pool_init(&pool, os.heap_allocator(), worker_count, init_proc, nil, fini_proc, nil)
	defer thread.pool_destroy(&pool)

	tasks := make([]Preload_Task, len(to_load), context.temp_allocator)
	thread.pool_start(&pool)
	for lang, i in to_load {
		tasks[i].lang = lang
		// Per-task context allocator = heap, so any stray context.allocator use
		// inside a worker is thread-safe.
		thread.pool_add_task(&pool, os.heap_allocator(), preload_worker, &tasks[i], i)
	}
	thread.pool_finish(&pool) // barrier: all workers joined before we return
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

