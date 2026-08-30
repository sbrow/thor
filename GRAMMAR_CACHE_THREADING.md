# Grammar cache thread-safety & allocator lifetime

Status: **investigation complete, fix deferred.** This document records what we
found and the direction we chose, so the next person doesn't have to rediscover
it. No behavior has been changed yet — only documentation comments were added to
`treesitter/treesitter.odin`.

## How we got here

While adding a feature to minify inline `<style>` blocks (route the CSS body
through `minify_css`), the new unit tests exercised `minify_html` / `minify_css`
for the first time. Those are the first tests to touch the tree-sitter parser
cache, and under the multi-threaded test runner (default 16 threads) they failed
**intermittently** with a rotating cast of symptoms:

- `panic: unable to insert into a map`
- tree-sitter internal aborts: `ts_subtree_retain: Assertion 'self.ptr->ref_count > 0' failed`, `_array__erase: Assertion 'index < *size' failed`
- `malloc(): unaligned tcache chunk detected`
- assertions passing on the wrong data (e.g. minified output missing `<style>`)

The flakiness comes from **three distinct problems**, two thread-safety and one
allocator-lifetime. They are orthogonal — fixing one does not fix the others.

## The three issues

### #1a — concurrent cache **writes** (data race)

`ensure_parser` (`treesitter.odin`) reads and writes `grammar_store.cache`
with **no lock**. `cache_mutex` exists but is only taken on the parallel preload
path (`grammar_worker`), never in the lazy `ensure_parser` / `load_grammar`
paths. Two threads first-touching `"html"`/`"css"` at once corrupt the map.

### #1b — concurrent parser **use** (data race)

There is exactly **one cached `Grammar_Cache` (and one `parser`) per language**.
When two threads both call `minify_html`, they fetch the *same* `gc.parser` and
call `parser_parse_string` on it simultaneously. A tree-sitter `TSParser`
mutates its internal subtree pool during a parse, so concurrent parses corrupt
it — that's the `ts_subtree_retain` / `_array__erase` aborts.

This is **not fixed by preloading/"loading html+css statically."** Loading gives
you *one shared* parser; the race is about *using* that one parser from two
threads. It is fixed only by serializing the parse or giving each thread its own
parser.

### #2 — allocator lifetime (not a race)

`init_persistent` captures `context.allocator` into the process-lifetime
`grammar_store`. In `main` that happens to be the heap (it runs before the site
arena is installed at `main.odin`), so production is fine. But whatever
allocator is live at that instant becomes the cache's owner forever:

- Under the **test runner**, `context.allocator` is a **per-test tracking
  allocator** that is torn down when that test ends → the global cache is left
  pointing at dead memory (→ `unable to insert into a map`, garbage reads).
- A **lazy** first call during rendering would capture the **site arena**
  (`context.allocator` after `main.odin` swaps it in), which is destroyed every
  watch-mode rebuild → dangling parsers across builds.

This would break even single-threaded; threading just decides *which* test wins
the init race.

## tree-sitter's threading model (the root fact)

tree-sitter objects have specific, documented threading rules:

| Object | Shareable across threads? | Rule |
|---|---|---|
| `TSLanguage` (`tree_sitter_html()` etc.) | Yes | Immutable; share freely. |
| `TSParser` (`gc.parser`) | **No** | One per thread; never parse on one parser from two threads. |
| `TSTree` | Only via `ts_tree_copy` | Copy before using on another thread. |
| `TSQuery` (`gc.query`) | Yes | Immutable after compile. |
| `TSQueryCursor` (`gc.cursor`) | **No** | One per thread, like the parser. |

This explains the existing design:

- The preload fan-out (`preload_grammar` / `grammar_worker`) creates a parser
  **per worker** and only publishes the finished `Grammar_Cache` under
  `cache_mutex` — because parsers can't be shared during construction/use.
- `ensure_parser` + the shared cached parser is fine in production **only
  because rendering is single-threaded**.

A cached `Grammar_Cache` mixes shareable (`language`, `query`) and per-thread
(`parser`, `cursor`) objects in one shared struct, which makes it
single-threaded-use by construction — a fact that was previously undocumented.

## Where this actually bites

**Only in tests.** Confirmed by grep:

- Production parses on one thread: every real caller — `minify.odin` (html/css)
  and `markdown/highlight.odin` — runs inside `main`'s single-threaded render
  loop. No concurrent `ensure_parser` / `parser_parse_string`.
- The one threaded path in production, `preload_grammars`, is already safe (own
  parser per worker + `cache_mutex` on the write) and only handles non-builtin
  grammars.
- Only `minify_test.odin` touches tree-sitter from tests, and the test runner
  runs those on many threads.

So production is correct **by convention** (single-threaded-from-heap usage),
not **by construction** — nothing stops a future parallel render from breaking
it, and until now nothing documented the constraint.

## Chosen direction

**For now:** keep the single global grammar cache and make it safe by
**serializing the non-thread-safe behavior with a mutex** — only one thread uses
a parser at a time. This is simple, matches how production already behaves, and
unblocks the tests.

**Later (TODO):** decide whether true multi-threaded parsing is worth it for
performance. If yes, give each thread its own parser + cursor (as the preload
workers already do) rather than sharing one behind a lock.

## Implementation options (deferred — pick when we resume)

All assume the allocator fix (#2) below, which is independent and unambiguous.

- **#2 allocator (do regardless):** pin the heap allocator explicitly —
  `grammar_store.allocator = runtime.heap_allocator()` (or `os.heap_allocator()`)
  instead of `context.allocator`. Makes the cache persistent from any context;
  behavior-identical in production. Optionally make `init_persistent` idempotent
  and/or an `@(init)` so callers need no ordering.

Then, for the races:

- **Option A — library mutex (sustainable):** take `cache_mutex` in
  `ensure_parser` (fixes #1a) and add a locking `parse` helper that wraps
  `parser_parse_string` (fixes #1b), wired into the three call sites
  (`minify.odin` ×2, `markdown/highlight.odin` ×1). Tests then need no
  scaffolding. Serializes all parsing.

- **Option B — test-side only (minimal):** leave the library single-threaded by
  contract; make the tests not violate it. Either fold the minify tests into one
  `@(test)` (no concurrency at all → no locks), or wrap the `minify_*` calls in a
  test-local mutex. Production stays lock-free.

Recommendation captured during the discussion: the allocator one-liner is
worth doing immediately; for the races, Option A is the "correct" long-term
answer but only necessary if/when we want concurrent parsing — otherwise
Option B is enough.

## Pointers

- `treesitter/treesitter.odin`: doc comments on `Grammar_Cache`, `cache_mutex`,
  `init_persistent`, `ensure_parser` reference this file.
- Original feature that surfaced this: minify inline `<style>` bodies via
  `minify_css` (reverted; to be re-landed alongside whichever fix we choose).
