# Parallelization Plan

## Current bottleneck

`compile_query` (which contains `query_new`) is ~100% of the grammar loading cost. With ~7 languages, sequential loading costs ~200-280ms. The rest of the build is ~12ms.

## Thread safety concerns

Current code is single-threaded and assumes it:
- `grammar_cache` map — concurrent writes unsafe
- `context.temp_allocator` — shared, not thread-safe
- `Site.pages` dynamic array — concurrent appends unsafe
- Site arena — bump pointer, not atomic

Any parallelization must address these.

## Dependency graph

```
init_site → build_vfs → scan_content (discover files)
  → grammar loading (must finish before any highlight_code)
  → load_page × N (markdown pipeline + highlight_code)
  → render_site (template rendering × N + minify × N)
  → RSS + sitemap (needs all pages loaded)
  → asset copying (independent)
```

Key barriers:
- Grammar loading must finish before any highlighting
- Pages must be loaded before rendering
- All pages must be rendered before RSS/sitemap
- Minify + write are independent per page after render

## Three approaches

### Option 1: Per-subsystem parallelism

```
Phase 1: Parallel grammar loading (7 threads)
Phase 2: Parallel content loading (N pages on M threads)
Phase 3: Parallel template rendering (N pages on M threads)
Phase 4: Parallel minification (N pages on M threads)
Phase 5: Sequential: RSS, sitemap, assets
```

Pros:
- Simple barriers — each phase completes before the next starts
- Easy to reason about

Cons:
- Thread pool setup/teardown per phase (or reuse a pool with barriers)
- Memory pressure: all pages loaded before any rendered
- Load imbalance within phases (complex pages vs simple)

### Option 2: Per-page parallelism

```
Pre-load all grammars (sequential or parallel)
Then for each page (in parallel):
    load_page → md.process → render → minify → write
Then sequential: RSS, sitemap, assets
```

Pros:
- Natural work unit — each page flows through the full pipeline independently
- No barriers between phases

Cons:
- Complex pages clog workers while simple pages finish fast
- Grammar loading must happen first (barrier)
- Needs thread-safe shared state (grammar cache, template cache, allocator)

### Option 3: Generic worker queue

```
Single thread pool with work stealing.
Jobs: grammar_load(lang), load_page(file), render_page(page), minify(html), write_output(path)
Dependencies tracked via futures or callbacks.
```

Pros:
- Most flexible — handles all work types
- Best load balancing (work stealing across types)
- No wasted thread setup between phases

Cons:
- Most complex to implement
- Need dependency tracking (can't render before load completes)
- Careful shared-state management needed
- Memory management with arena allocator (thread safety)

## Recommended starting point

**Pre-load grammars in parallel, keep everything else sequential.**

```
Phase 0: Pre-scan content for unique languages (fast, sequential)
Phase 1: Parallel grammar loading (one thread per language, ~30ms)
         → each thread writes to a pre-assigned slot (no map contention)
         → each thread uses its own temp allocator
         → main thread merges results into grammar_cache after join
Phase 2: Sequential build as today (~12ms)
```

Expected: ~42ms total instead of ~210ms. Minimal architecture change — no thread-safe allocators needed for the rest of the pipeline.

This can later evolve toward option 3 (generic queue) if page count grows or per-page processing becomes a bottleneck.

## Implementation notes

- Odin's `core:thread` or `core:sync` can manage the thread pool
- Each grammar-loading thread needs its own `context.temp_allocator` for path strings
- The `grammar_cache` map write happens on the main thread after all threads join
- `dlopen` is thread-safe (POSIX guarantee)
- `query_new` is likely thread-safe (independent computation per language, no shared state in tree-sitter)
