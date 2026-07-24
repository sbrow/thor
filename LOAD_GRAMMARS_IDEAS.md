# load_grammar Optimization Ideas

## Current bottleneck

`load_grammar` is called once per unique language on first use. Each call costs ~30-40ms:
- `dlopen` — loads `.so` from disk (dominant)
- `read_entire_file_from_path` — reads `.scm` from disk
- `query_new` — compiles query
- `query_cursor_new` — allocates cursor (cheap)

With ~7 languages, first-load cost is ~210-280ms. Subsequent calls hit cache (~0ms).

## Code-level optimizations

### Avoid double-cloning query source

Currently: `read_entire_file_from_path` → `[]byte` → `string(raw)` → `strings.clone_to_cstring(query_src)`. Two copies of the entire `.scm` file.

Fix: read into a buffer with a trailing null byte, use directly as cstring. One read, zero copies.

### Reuse the grammar path string

`fmt.tprintf("%s/%s.so", grammar_dir, lang)` is computed in `ensure_parser` AND again in error diagnostics (line 284). Compute once, store in `Grammar_Cache`.

### Avoid `fmt.tprintf` for symbol name

`"tree_sitter_" + lang` can be simple concatenation instead of format string parsing.

### Extract error diagnostics to a separate proc

The query error diagnostics (lines 250-300) make up more than half of `load_grammar`. Extract to `report_query_error(lang, query_src, err_offset, err_type, query_path)`. Makes `load_grammar` focused on the happy path.

## Architectural optimizations

### Pre-scan content for languages, then batch-load

Before rendering, scan all markdown for `language-X` code blocks. Collect the unique set. Load all grammars in one pass.

Benefits:
- Makes cost visible ("loading grammars for: bash, odin, nu...")
- Enables parallel loading
- Moves cost to a predictable point in the build

### Parallel grammar loading

`dlopen` is thread-safe (POSIX). Load N grammars on N threads simultaneously.

- Sequential: ~210ms (7 languages × ~30ms each)
- Parallel (4 cores): ~60ms
- Parallel (7 threads): ~30ms

Biggest single win for first-load time. Odin's `core:thread` or `core:sync` can manage the thread pool.

### Static-link more grammars

Extend the `mkGrammarStaticLib` pattern (already used for HTML/CSS in `flake.nix`) to bash, odin, nu, etc.

- Zero `dlopen` — grammars baked into binary
- Zero `read_entire_file_from_path` — queries embedded via `#load` or `#directory`
- Zero `query_new` compilation — could pre-compile or use compile-time embedding
- Downside: binary size grows (~500KB per language), adding languages requires recompiling

### Embed queries at compile time

Even without static-linking grammars, the `.scm` query files could be embedded via `#load` or `#directory`.

- Eliminates `read_entire_file_from_path` per language
- Smaller win than static linking but simpler
- Queries are small text files (~2-10KB each)

### Cache compiled queries across runs

`query_new` compiles the `.scm` source into an internal representation. If this could be serialized and cached to disk (like a `.thorcache`), subsequent builds could skip compilation.

- Tree-sitter's query format isn't documented as serializable — would need investigation
- Even if not serializable, caching the raw `.scm` source in memory avoids re-reading from disk in watch mode (already handled by `grammar_cache` persistence)

### Pre-link common grammars in the flake

The flake could compile grammar `.so` files as Nix build inputs and pass their paths to thor at runtime via the `grammars` config field. This doesn't eliminate `dlopen` but ensures the files are always available in the Nix store.

## Priority ranking

1. **Parallel grammar loading** — immediate ~4-7x speedup on first load, no binary changes
2. **Static-link common grammars** — eliminates the problem entirely, but requires flake work
3. **Pre-scan + batch-load** — enables parallel loading and better UX logging
4. **Avoid double-clone of query source** — quick code cleanup, small win
5. **Embed queries at compile time** — eliminates file reads, moderate effort
