# Thor — Odin Static Site Generator

Thor is a static site generator written in [Odin](https://odin-lang.org), replacing Hugo for the `sbrow.github.io` blog. It lives at `./thor/` as a git subtree with its own `flake.nix`.

## Architecture

```
thor.json          ← site config (title, base_url, author, params, sectionate)
content/           ← markdown and HTML content files
layouts/           ← Mustache templates + partials (including icons)
assets/            ← CSS (Tufte-based, no build step) and JS
public/            ← build output (generated)
```

### Source files

| File | Responsibility |
|---|---|
| `main.odin` | Entry point. Sets `context.logger`, calls `init_site`, `walk_content`, `render_site` |
| `site.odin` | `Site` struct (config + arena), `init_site`, `load_site_config`, `site_merge`, `site_allocator`, `destroy_site` |
| `frontmatter.odin` | JSON frontmatter parser (`{ }` delimited) |
| `content.odin` | `Page` struct, content walker, page loader, cmark integration, full markdown pipeline |
| `footnotes.odin` | Note definition stripping (pre-cmark) + sidenote/marginnote injection (post-cmark) |
| `alerts.odin` | GitHub alert post-processor (`> [!CAUTION]` → styled blockquote) |
| `emoji.odin` | Emoji shortcode expander (`:shrug:` → `¯\_(ツ)_/¯`), post-cmark |
| `highlight.odin` | Post-cmark Tree-sitter syntax highlighter; loads grammars/queries from Helix, caches loaded grammars, reports syntax errors with file/line |
| `tree_sitter.odin` | C FFI bindings for Tree-sitter (TSParser, TSQuery, TSQueryCursor, node traversal, dlopen/dlsym) |
| `sectionate.odin` | `wrap_sections` proc — splits HTML at `<h2` into `<section>` wrappers |
| `render.odin` | Mustache template rendering, all page types, RSS, sitemap, robots.txt, `load_partials` recursive scan |
| `feed.odin` | RSS feed + sitemap XML generation |
| `mustache/` | Mustache template engine (spec-compliant, replaces vendored odin-mustache) |

Icon SVGs live as HTML partials in `layouts/partials/icons/` (home, github, rss, chevron_up, star).

### Data flow

```
thor.json → init_site → Site (config + Dynamic_Arena)
                            ↓
content/ → walk_content → []Page (with body_html from pipeline)
                            ↓
layouts/*.html → render_site (Mustache render_in_layout) → public/
```

### Config system

`Site` has `params: json.Value` for arbitrary user-defined data from `thor.json`. Social links and other template-only data live under `"params"`. `sectionate: bool` controls automatic `<section>` wrapping at `<h2>` boundaries.

```json
{
  "title": "...",
  "base_url": "...",
  "author": "...",
  "sectionate": true,
  "params": {
    "social": [
      { "name": "github", "url": "...", "icon": "icons/github" }
    ]
  }
}
```

Templates access params via dotted keys: `{{#params.social}}`, `{{>* icon}}`.

Config precedence: `CLI flags > thor.json values > hardcoded defaults`.

### Markdown pipeline (in content.odin `load_page`)

```
raw markdown
  → expand_emoji          (pre-cmark: :shortcode: → unicode)
  → strip_definitions     (pre-cmark: extract [^id]: definitions)
  → cmark markdown_to_html (Unsafe mode for HTML passthrough)
  → expand_emoji          (post-cmark: :shortcode: → unicode, avoids cmark escape issues)
  → inject_sidenotes      (post-cmark: [^id] → <label><input><span> markup)
  → inject_alerts         (post-cmark: [!TYPE] blockquotes → styled alerts)
  → highlight_code        (post-cmark: tree-sitter per code block, with error reporting)
  → wrap_sections         (post-cmark: if site.sectionate, wraps content in <section> at <h2>)
```

`.html` content files skip cmark entirely — body is used as-is.

### Syntax highlighting

Build-time highlighting via Tree-sitter C FFI. No client-side JavaScript.

- Grammars loaded via `dlopen` from Helix's compiled `.so` files
- Highlight queries (`.scm`) loaded from Helix's runtime directory
- Paths hardcoded in `tree_sitter.odin` (Nix store paths, Helix-version-dependent)
- Capture names mapped to CSS classes: `keyword` → `.hl-keyword`, `constant.numeric.integer` → `.hl-constant-numeric-integer`, etc.
- Atom-one-dark color theme in `main.css`
- Failed grammar loads are cached (no retries) and logged via `log.warnf`
- Syntax errors detected via `ts_node_has_error`, reported with file path and line number relative to code block

### Memory management

- `Site` owns a `mem.Dynamic_Arena`
- `init_site` calls `mem.dynamic_arena_init(&site.arena, alignment = 64)` — the 64-byte alignment is required by Odin's map runtime (`MAP_CACHE_LINE_SIZE`)
- Config loading (flags + JSON) uses the arena allocator explicitly
- `site_allocator(site)` returns the arena allocator for callers
- `destroy_site` frees the arena
- `main.odin` sets `context.logger = log.create_console_logger()` — without this, all `log.*` calls are silently dropped
- **Not yet wired:** `context.allocator` is not set to the arena in `main.odin`, so rendering and content processing still use the heap allocator

## Building

### Local development

```bash
nix develop
# From blog root:
odin run ./thor -- -drafts
cp assets/css/main.css public/css/main.css
cp assets/js/main.js public/js/main.js
caddy run  # serves public/ on blog.localhost
```

No CSS build step — `main.css` is static Tufte-based CSS, no preprocessor or compiler needed.

### Production build

```bash
nix build  # runs thor + copies CSS/JS, outputs to ./result/
```

### Tests

```bash
cd thor
odin test .           # site + mustache smoke tests
odin test mustache    # mustache spec + targeted tests (37 total)
```

## Mustache engine

Spec-compliant Mustache implementation at `mustache/`. Passes all 170 tests across 7 official spec files (interpolation, sections, inverted, comments, partials, dynamic-names, inheritance).

### Files

| File | Responsibility |
|---|---|
| `mustache.odin` | Public API (`parse`, `render`, `Template`), parser (`parse_section`), post-parse de-indent (`deindent_blocks`), renderer (`render_nodes`), indent helpers |
| `tokenizer.odin` | Tokenizer (template string → `[]Token`), two-pass standalone whitespace detection (`trim_standalone_whitespace`) |
| `data.odin` | Reflection-based data model: `effective` (union/distinct peeling), `lookup_in`, `resolve_name`, `is_truthy`, `any_to_string`, `list_info`, `write_value`, `format_f64` |
| `spec_test.odin` | JSON spec test runner — loads `spec/specs/*.json`, runs each test case |

### Architecture

```
parse(source) → tokenize → trim_standalone_whitespace → parse_section → deindent_blocks → Template
render(tmpl, data, partials) → render_nodes (walks flat node array against context stack) → string
```

- **Flat `[dynamic]Node` array** with `first_child`/`child_count` indices — one allocation, one `delete`. Pre-order layout: children stored contiguously after their parent.
- **`render_nodes`** takes `all_nodes` (full array, for absolute child access) + `nodes` (current slice). Index-based loop, skips children after sections/blocks via `i += 1 + child_count`.
- **Context stack**: `^[dynamic]any` with `append`/`pop` for section push/pop.
- **`effective(a)`** peels Named/Distinct/Union layers (including `json.Value`) so all downstream operations can switch on base `Type_Info` variant directly.
- **Two-pass standalone detection**: detect using original token values, then trim left-to-right with `left_done`/`right_done` tracking to prevent double-trims. Cascading `check_left`/`check_right` skip adjacent standalone-eligible tags.
- **Block indent**: `deindent_blocks` runs post-parse — finds common indent of direct text children, sets block's intrinsic indent if empty, removes common indent. Renderer applies block indent at output level via `write_indented`.
- **Partial/parent indent**: `Template` stores `source` for indent re-parse. `render_template` calls `indent_lines(source, indent)` then re-parses with temp allocator when indent is non-empty.
- **Block overrides** (`Block_Override` struct): carries `all_nodes` + child range so override content from different templates renders correctly. `merge_block_overrides` propagates overrides through multi-level inheritance chains.

### Not implemented

- Lambdas (`~lambdas.json`)
- Set delimiters (`{{= =}}`, `delimiters.json`)

## Known limitations

- cmark allocates via C malloc, not the arena. HTML output leaks until process exit.
- CSS/JS cache busting uses manual `?v=N` query params instead of content hashing.
- `json.Value` params require 64-byte aligned arena (workaround for `dynamic_arena_allocator_proc` ignoring per-allocation alignment).
- Tree-sitter grammar/query paths hardcoded in `tree_sitter.odin` (Nix store hashes, Helix-version-dependent).
- `TSQueryCapture` needs explicit `_padding: u32` field for C ABI compatibility (40-byte sizeof).
- highlight.js removed; syntax highlighting is build-time only (no fallback if Tree-sitter fails).
- `format_f64` in mustache brute-forces shortest float representation (Odin's `strconv` doesn't produce shortest round-trip for all values like `3.3`).
- Block indent uses output-level indentation (`write_indented`), not source-level re-parse. Multi-line interpolated content inside a standalone block would get incorrectly indented. No spec test exercises this.

## Design decisions

See `HUGO.md` for analysis of why thor doesn't need Hugo's shortcode context isolation.
See `mustache/PARTIAL_INDENT.md` for whitespace handling analysis.
See `mustache/SPEC.md` for the original implementation specification.

## TODO

See `TODOS.md` for the full list.
