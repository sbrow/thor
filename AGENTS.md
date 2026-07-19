# Thor — Odin Static Site Generator

Thor is a static site generator written in [Odin](https://odin-lang.org), replacing Hugo for the `sbrow.github.io` blog. It lives at `./thor/` as a git subtree with its own `flake.nix`.

## Architecture

```
thor.json          ← site config (title, base_url, author, params)
content/           ← markdown and HTML content files
layouts/           ← Mustache templates + partials (including icons)
assets/            ← CSS (Tufte-based), JS, fonts, images — copied/processed to public/
public/            ← build output (generated)
```

### Source files

| File | Responsibility |
|---|---|
| `main.odin` | Entry point. Sets `context.logger`, calls `init_site`, `walk_content`, `render_site`. Optional Spall profiling via `SPALL` config flag. |
| `site.odin` | `Flags` (CLI args), `Config_File` (from `thor.json`), `Site` (runtime state + arena), `Feature` + `Markdown_Extension` bit_set enums, `DEFAULT_MARKDOWN_EXTENSIONS`, 5-step `init_site` (defaults → flags → config → apply config → apply flags), `load_config_file`, `apply_config`, `apply_cli_flags`, `parse_extension_list`, `find_config` |
| `frontmatter.odin` | JSON frontmatter parser (`{ }` delimited) |
| `content.odin` | `Page` struct, content walker, page loader, cmark integration, full markdown pipeline, `copy_assets_dir` (recursive copy with CSS minification) |
| `footnotes.odin` | Note definition stripping (pre-cmark) + sidenote/marginnote injection (post-cmark) |
| `alerts.odin` | GitHub alert post-processor (`> [!CAUTION]` → styled blockquote) |
| `emoji.odin` | Emoji shortcode expander (`:shrug:` → `¯\_(ツ)_/¯`), post-cmark |
| `highlight.odin` | Post-cmark Tree-sitter syntax highlighter; statically links HTML/CSS grammars, dlopen for others; caches loaded grammars, reports syntax errors |
| `tree_sitter.odin` | C FFI bindings for Tree-sitter (TSParser, TSQuery, TSQueryCursor, node traversal, dlopen/dlsym). Statically links `tree-sitter-html` and `tree-sitter-css` via Nix. |
| `sectionate.odin` | `wrap_sections` proc — splits HTML at `<h2` into `<section>` wrappers |
| `render.odin` | Template rendering pipeline: pre-parses templates/partials once, struct-based data model (`Base_Data`/`Page_Data`/`Home_Data`/`Posts_Data`), `mustache.render()`, minification gate, RSS, sitemap, robots.txt |
| `minify.odin` | Tree-sitter-based HTML and CSS minification (`minify_html`, `minify_css`). Strips comments, collapses whitespace, removes inter-tag spaces. Preserves `<pre>`/`<code>`/`<script>`/`<style>` content. |
| `feed.odin` | RSS feed + sitemap XML generation. Uses `strings.Builder`. `format_rfc822` uses `core:time` for date parsing. |
| `mustache/` | Mustache template engine (spec-compliant, custom implementation) |

Icon SVGs live as HTML partials in `layouts/partials/icons/` (home, github, rss, chevron_up, star).

### Data flow

```
thor.json → find_config → init_site:
  1. set defaults (base_url, DEFAULT_MARKDOWN_EXTENSIONS)
  2. parse CLI flags (Flags struct)
  3. load config file (Config_File from thor.json)
  4. apply_config — non-empty config fields override defaults
  5. apply_cli_flags — flags override config, -ext/-no-ext adjust extensions
→ Site (config + Dynamic_Arena + features: bit_set + markdown_extensions: bit_set)
                                                                                               ↓
content/ → walk_content → []Page (with body_html from pipeline)
                                                                                               ↓
layouts/*.html → parse() → mustache.Template (parsed once)
                                   ↓
render_site → mustache.render(Page_Data, partials) → optional minify_html → public/
```

### Config system

Config is split into three structs with a clear 5-step initialization flow:

- **`Flags`** — CLI args only. Parsed by `core:flags`. Includes path overrides, build-mode toggles, and `-ext`/`-no-ext` for markdown extension overrides.
- **`Config_File`** — parsed from `thor.json` via `json.unmarshal_string`. Holds title, paths, `markdown_extensions` (JSON), `params` (JSON).
- **`Site`** — runtime state: arena, resolved config values, `features: bit_set[Feature]`, `markdown_extensions: bit_set[Markdown_Extension]`.

**`Feature` enum** — build-mode toggles: `Drafts`, `Minify`, `Watch`. Checked with `.Minify in site.features`.

**`Markdown_Extension` enum** — content pipeline toggles: `Emoji`, `Sidenotes`, `Alerts`, `Highlight`, `Sections`. Default is `DEFAULT_MARKDOWN_EXTENSIONS` (currently `.Emoji, .Sidenotes, .Alerts`). Configurable via:
- `thor.json`: `"markdown_extensions": { "emoji": true, "highlight": false, ... }`
- CLI: `-ext:highlight,sections` (enable) / `-no-ext:emoji` (disable). Comma-separated, case-insensitive.

**`find_config`** — walks up from CWD looking for `thor.json`. Falls back to `./thor.json`.

Config precedence: `CLI flags > thor.json values > hardcoded defaults`.

```json
{
  "title": "...",
  "base_url": "...",
  "author": "...",
  "markdown_extensions": {
    "emoji": true,
    "sidenotes": true,
    "alerts": true,
    "highlight": true,
    "sections": true
  },
  "params": {
    "social": [
      { "name": "github", "url": "...", "icon": "icons/github" }
    ]
  }
}
```

### Template system

Templates use Mustache with template inheritance (`{{<base}}` / `{{$block}}`):

```html
<!-- base.html -->
<body>{{> nav}}{{$content}}{{/content}}{{> footer}}</body>

<!-- post.html -->
{{<base}}
{{$content}}
<main><article><h1>{{page_title}}</h1>{{&body}}</article></main>
{{/content}}
{{/base}}
```

Data is passed as **typed structs** (not `map[string]any`). Mustache resolves struct fields via Odin reflection, including `using`-embedded fields. Date presence is checked via string truthiness (`{{#date_iso}}`) — no separate `has_date` bool needed.

```odin
Base_Data :: struct {
    now:  datetime.DateTime,
    body: string,
    title: string,
    // ...
}
Page_Data :: struct {
    using base: Base_Data,  // fields promoted via struct_get fallback
    page_title: string,
    // ...
}
```

`render_site` pre-parses all templates and partials once (via `mustache.parse`), then reuses them for every page render.

### Markdown pipeline (in content.odin `load_page`)

```
raw markdown
  → strip_definitions     (pre-cmark: extract [^id]: definitions — only if .Sidenotes enabled)
  → cmark markdown_to_html (Unsafe mode for HTML passthrough)
  → expand_emoji          (post-cmark: :shortcode: → unicode — only if .Emoji enabled)
  → inject_notes          (post-cmark: [^id] → <label><input><span> markup — only if .Sidenotes enabled)
  → inject_alerts         (post-cmark: [!TYPE] blockquotes → styled alerts — only if .Alerts enabled)
  → highlight_code        (post-cmark: tree-sitter per code block — only if .Highlight enabled)
  → wrap_sections         (post-cmark: wraps content in <section> at <h2> — only if .Sections enabled)
```

Each step is gated by `bit_set[Markdown_Extension]`. All `.html` content files skip the pipeline entirely — body is used as-is.

### Syntax highlighting

Build-time highlighting via Tree-sitter C FFI. No client-side JavaScript.

- **HTML and CSS grammars** statically linked via Nix (`mkGrammarStaticLib` in `thor/flake.nix`). Always available, no dlopen.
- **Other grammars** (bash, odin, nu, etc.) loaded via `dlopen` from Helix's compiled `.so` files.
- Highlight queries (`.scm`) loaded from Helix's runtime directory.
- Paths hardcoded in `tree_sitter.odin` (Nix store paths, Helix-version-dependent).
- Grammar loading split: `ensure_parser` (parser only, used by minify) vs `load_grammar` (parser + query, used by highlight).
- Capture names mapped to CSS classes: `keyword` → `.hl-keyword`, etc.
- Atom-one-dark color theme in `main.css`.

### Minification

Optional, enabled with `-minify` flag (`.Minify` in `Feature` bit_set).

- **HTML** — tree-sitter parses output, strips comments, removes inter-tag whitespace, preserves `<pre>`/`<code>`/`<textarea>`/`<script>`/`<style>` content. Applied after template rendering.
- **CSS** — tree-sitter parses `.css` files in `assets/`, strips comments, collapses whitespace, trims around `{};:,`. Applied during `copy_assets_dir`.
- Non-CSS files in `assets/` copied verbatim.

### Memory management

- `Site` owns a `mem.Dynamic_Arena`
- `init_site` calls `mem.dynamic_arena_init(&site.arena, alignment = 64)` — the 64-byte alignment is required by Odin's map runtime (`MAP_CACHE_LINE_SIZE`)
- Config loading (flags + JSON) uses the arena allocator explicitly
- `site_allocator(site)` returns the arena allocator for callers
- `destroy_site` frees the arena
- `main.odin` sets `context.logger = log.create_console_logger()` — without this, all `log.*` calls are silently dropped
- `context.allocator` is set to `site_allocator(&site)` in the main loop

### Spall profiling

Optional, compiled out by default. Enabled with `-define:SPALL=true`:

```bash
odin build . -define:SPALL=true -o:speed -out:thor-prof
./thor-prof -drafts  # generates thor.spall
```

Uses `core:prof/spall` with `@(instrumentation_enter)`/`@(instrumentation_exit)` hooks — every function auto-instrumented, no manual annotation needed.

## Building

### Local development

```bash
nix develop
# From blog root:
odin run ./thor -- -drafts
# Assets (CSS/JS/fonts) are copied/minified automatically by thor
caddy run  # serves public/ on blog.localhost
```

No CSS build step — `main.css` is static Tufte-based CSS, no preprocessor or compiler needed.

### Production build

```bash
nix build  # runs thor, outputs to ./result/
```

### Tests

```bash
cd thor
odin test .              # site tests (config, frontmatter, footnotes)
odin test . -all-packages  # includes mustache spec tests
```

## Mustache engine

Spec-compliant Mustache implementation at `mustache/`. See `mustache/SPEC.md` for the implementation specification.

### Files

| File | Responsibility |
|---|---|
| `mustache.odin` | Public API (`parse`, `render`, `Template`), parser (`parse_section`), renderer (`render_nodes`), template inheritance (`merge_block_overrides`) |
| `tokenizer.odin` | Tokenizer (template string → `[]Token`), standalone whitespace detection |
| `data.odin` | Reflection-based data model: `effective` (union/distinct peeling), `lookup_in`, `resolve_name`, `is_truthy`, `any_to_string`, `list_info`, `write_value` |
| `spec_test.odin` | JSON spec test runner — loads `spec/specs/*.json`, runs each test case |

### Architecture

```
parse(source) → tokenize → trim_standalone_whitespace → parse_section → Template
render(tmpl, data, partials) → render_nodes (walks flat node array against context stack) → string
```

- **Two-phase API**: `parse()` produces a reusable `Template`, `render()` walks it against data. Templates parsed once, rendered many times.
- **Flat `[dynamic]Node` array** with `first_child`/`child_count` indices — pre-order layout.
- **Context stack**: `^[dynamic]any` with `append`/`pop` for section push/pop.
- **`effective(a)`** peels Named/Distinct/Union layers (including `json.Value`).
- **`lookup_in`** resolves keys on structs (via `reflect.struct_field_value_by_name` with `allow_using = true`) and maps (via runtime map internals).
- **Template inheritance**: `{{<parent}}` loads parent from partials, `{{$block}}` defines overridable sections. `merge_block_overrides` propagates overrides through multi-level chains.
- **Dynamic partial names**: `{{>*key}}` resolves partial name from data context at render time.

### Not implemented

- Lambdas (`~lambdas.json`)
- Set delimiters (`{{= =}}`, `delimiters.json`)

## Known limitations

- cmark allocates via C malloc, not the arena. HTML output leaks until process exit.
- CSS/JS cache busting uses manual `?v=N` query params instead of content hashing.
- Tree-sitter grammar/query paths for dynamic grammars hardcoded in `tree_sitter.odin` (Nix store hashes, Helix-version-dependent). HTML/CSS are statically linked.
- `map[string]any` not fully supported by mustache `lookup_in` — thor uses structs instead.
- `format_f64` in mustache brute-forces shortest float representation.

## Design decisions

You may never, *ever* remove `TODO:` or `FIXME:` comments. Those are for humans, not machines.
See `HUGO.md` for analysis of why thor doesn't need Hugo's shortcode context isolation.
See `mustache/PARTIAL_INDENT.md` for whitespace handling analysis.
See `mustache/SPEC.md` for the original implementation specification.

## TODO

See `TODOS.md` for the full list.
