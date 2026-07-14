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
| `mustache/` | Vendored [odin-mustache](https://github.com/benjamindblock/odin-mustache) library |

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

## Vendored mustache patches

Four modifications to `mustache/mustache.odin`:

1. **`any` unwrapping** in `map_get` and `data_type` — when values come from `map[string]any`, the inner `any` wrapper is unwrapped so type detection works correctly for nested maps and lists.

2. **Layout partials** — `layout_template.partials = tmpl.partials` added so partials (`{{> nav}}`, `{{> footer}}`) work inside the base layout template.

3. **Inline partial rendering** — replaced `template_insert_partial` (which injected tokens into the main token list, breaking section iteration) with `template_render_partial` (which lexes the partial, temporarily swaps `tmpl.lexer`, and recursively processes via `template_process_tokens`). Fixes partials inside sections. Standalone indentation applied to partial source before lexing.

4. **Dynamic Names** — `{{>*key}}` support. When a partial token value starts with `*`, the remaining key is resolved from the data context stack, and the resolved string is used as the partial name. Enables per-item partial selection inside sections (e.g., `{{>* icon}}` resolves `icon` from each social link).

Extracted `template_process_tokens` from `template_eat_tokens` to separate ROOT initialization + skip pass from the core token loop, allowing partials to reuse the loop.

## Known limitations

- cmark allocates via C malloc, not the arena. HTML output leaks until process exit.
- CSS/JS cache busting uses manual `?v=N` query params instead of content hashing.
- `json.Value` params require 64-byte aligned arena (workaround for `dynamic_arena_allocator_proc` ignoring per-allocation alignment).
- Tree-sitter grammar/query paths hardcoded in `tree_sitter.odin` (Nix store hashes, Helix-version-dependent).
- `TSQueryCapture` needs explicit `_padding: u32` field for C ABI compatibility (40-byte sizeof).
- `{{&content}}` in layout template must have no leading whitespace — `template_insert_content_into_layout` indents all lines by preceding whitespace, which corrupts `<pre>` blocks.
- highlight.js removed; syntax highlighting is build-time only (no fallback if Tree-sitter fails).

## Design decisions

See `HUGO.md` for analysis of why thor doesn't need Hugo's shortcode context isolation.

## TODO

See `TODOS.md` for the full list.
