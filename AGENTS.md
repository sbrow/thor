# Thor — Odin Static Site Generator

Thor is a static site generator written in [Odin](https://odin-lang.org), replacing Hugo for the `sbrow.github.io` blog. It lives at `./thor/` as a git subtree with its own `flake.nix`.

## 🚫 DO NOT EDIT THE DOCS — BY HUMANS, FOR HUMANS

> **THE DOCUMENTATION UNDER `thor/site/` IS HANDWRITTEN, BY HUMANS, FOR HUMANS.**
>
> **NO AI, AGENT, BOT, ASSISTANT, OR OTHER NON-HUMAN MAY EDIT, REWRITE,
> REPHRASE, REFORMAT, "IMPROVE," SUMMARIZE, OR GENERATE ANY FILE UNDER
> `thor/site/` — EVER.**
>
> These are not machine artifacts. A human wrote every word. AI may be
> consulted as a sanity check, but the prose stays human. If you are not a
> human, do not touch these files. See `thor/site/content/ai.md`.

## Architecture

```
thor.json          ← site config (title, base_url, params, modules, og)
content/           ← markdown and HTML content files
layouts/           ← Mustache templates + partials (user overrides)
assets/            ← CSS (Tufte-based), JS, fonts, images
thor/defaults/     ← bundled default templates (embedded via #directory)
public/            ← build output (generated)
```

### Package structure

```
thor/
├── treesitter/         # FFI types + grammar management (standalone package)
├── markdown/           # Content transformation pipeline (imports ../treesitter)
├── mustache/           # Template engine with lambdas + pipe filters + diagnostics
├── content.odin        # Page struct, Pending_File, scan_content_files, collect_languages, load_page
├── render.odin         # Template rendering, Template_Context, sort_pages, RSS, sitemap
├── menus.odin          # Menu_Entry, DEFAULT_WEIGHT, build_menus, collect_auto_menus, merge_page_menus, parse_page_menus, parse_config_menus
├── site.odin           # Config (Flags, Config_File, Site, Site_Context), init_site
├── minify.odin         # HTML/CSS minification (imports treesitter)
├── feed.odin           # RSS + sitemap generation
├── vfs.odin            # Union file system (defaults → modules → site)
├── assets.odin         # VFS-based asset copying
├── html.odin           # HTML helpers: strip_html_tags, unescape_html, generate_summary, generate_description
├── opengraph.odin      # Open_Graph struct + og_for_site/og_for_page
├── frontmatter.odin    # JSON frontmatter parser (supports nested og + lastmod + weight + menus)
├── defaults.odin       # DEFAULTS_PATH constant (#directory)
├── main.odin           # Entry point
├── bench/              # Template rendering benchmark
└── defaults/layouts/   # Bundled default templates
```

### Source files (main package)

| File | Responsibility |
|---|---|
| `main.odin` | Entry point. Parses CLI flags via `core:flags`, sets logger level from `-verbose`/`-quiet`, calls `init_site`, `build_vfs`, wires `treesitter.grammar_dir`/`query_dir` from config, `site_load_content`, `render_site`. Optional Spall profiling via `SPALL` config flag. |
| `site.odin` | `Flags` (CLI, includes `-verbose`/`-quiet`), `Config_File` (thor.json), `Site_Context` (template-facing: `title`, `description`, `base_url`, `params`, `og`, `menus`), `Site` (runtime state + arena + VFS + pages + `og`). `Feature` enum. `init_site(site, flags)` — takes pre-parsed `Flags`. Config menu parsing in `site_apply_config`. |
| `content.odin` | `Page` struct (includes `weight`, `menus`, `params: json.Value`, `toc: string`, `og`), `Pending_File` struct, `scan_content_files` (section-aware walk that handles leaf bundles), `collect_languages` (pre-scan for code fence languages), `load_page` (falls back to file mtime, generates TOC via `md.generate_toc` when frontmatter `"toc": true`), `infer_layout`. Calls `md.process()` for the markdown pipeline. |
| `render.odin` | Template rendering: `render_site`, `render_page_html`, `render_home_html`, `render_section`. `Template_Context` (unified render struct with `site: Site_Context`, `page: Page`, `menus`, `params`, `posts`, `pages`). 3-frame context stack via `[]any{ctx.site, ctx.page, ctx}`. `merge_params(site, page)` — shallow merge of site + page params. Error deduplication via `seen: ^map[string]bool` passed through render chain. `sort_pages` (weight primary, date secondary). `to_title_case` for section display names. VFS-based template loading with fallback chain (`get_template`). |
| `menus.odin` | Menu system: `Menu_Entry {name, url, weight: Maybe(int)}`, `DEFAULT_WEIGHT = 10`. `build_menus` (priority chain: config → auto + page frontmatter, then `warn_all_duplicate_weights`). `collect_auto_menus` (sections + root-level pages, skips pages with explicit `"menus": "main"` frontmatter). `merge_page_menus` (frontmatter entries with effective weight fallback via nil check). `parse_page_menus` (string/array/object forms). `parse_config_menus` (from thor.json). `sort_menu_entries` / `compare_menu_entries` (weight primary via `.? or_else DEFAULT_WEIGHT`, name secondary). `warn_duplicate_weights` / `warn_all_duplicate_weights` (log when two entries in same menu have same explicitly-set weight). |
| `minify.odin` | HTML/CSS minification via tree-sitter. Imports `ts "treesitter"`. |
| `feed.odin` | RSS feed + sitemap XML. Uses `page.url` for canonical URLs. |
| `vfs.odin` | Union file system: `VFS`, `build_vfs`, `mount_dir`, `mount_subdir`, `mount_recursive`, `vfs_get`, `vfs_get_entry`, `vfs_entry_data`. Layers defaults → modules → site. |
| `assets.odin` | `copy_assets_dir` — iterates VFS entries with `assets/` prefix, minifies CSS, copies verbatim or via `os.copy_file`. |
| `html.odin` | `strip_html_tags`, `unescape_html`, `generate_summary` (word-count truncation, zero-alloc), `generate_description` (HTML→plain text: strip tags, decode entities, collapse whitespace). |
| `opengraph.odin` | `Open_Graph` struct (fields ordered per OGP spec, `is_article: Maybe(bool)`). `og_for_site(site)` for site defaults (from config + derived), `og_for_page(site_og, page)` for page-specific (overlay page.og + derive from page data). Description falls back to `generate_description(generate_summary(body_html))`. |
| `frontmatter.odin` | JSON frontmatter parser (`{ }` delimited). Supports `layout`, `lastmod`, `weight: Maybe(int)`, `menus`, `params: json.Value`, `toc: bool`, and nested `og` object (via `json_get_open_graph`). Helpers: `json_get_string`, `json_get_bool`, `json_get_int` (returns `Maybe(int)`, nil for absent/invalid). |
| `defaults.odin` | `DEFAULTS_PATH` constant, resolved at compile time via `#directory` so bundled templates ship in the binary. |

### Subpackages

| Package | Files | Responsibility |
|---|---|---|
| `treesitter/` | `treesitter.odin` | FFI types (`Parser`, `Node`, `Query`, etc.), `@(link_prefix="ts_")` foreign bindings, grammar management (`Grammar_Store` with persistent allocator, `load_language`/`compile_query` building blocks, `ensure_parser`/`load_grammar` lazy loading, `preload_grammar`/`preload_grammars` for parallel loading with `sync.Mutex` cache protection), statically-linked HTML/CSS grammars |
| `markdown/` | `markdown.odin` | `Extension` enum, `DEFAULT_EXTENSIONS`, `process(body, ext, file_path, allocator)` — full pipeline (clones cmark output, frees original), `parse_extension_list`, `apply_extension_config` |
| | `footnotes.odin` | `strip_definitions` (pre-cmark, shared by `.Sidenotes` + `.Footnotes`), `inject_notes` (post-cmark sidenote rendering), `inject_footnotes` (post-cmark standard footnote rendering — numbered `<sup>` links + `<section class="footnotes"><ol>` at bottom). `.Sidenotes` and `.Footnotes` are mutually exclusive; `resolve_extension_conflicts` in `markdown.odin` picks `.Footnotes` if both are set. |
| | `alerts.odin` | `inject_alerts` — GitHub alert blocks (`> [!NOTE]`) → styled blockquotes with semantic class names (`alert-note` etc.) |
| | `emoji.odin` | `expand_emoji` — `:shortcode:` → unicode emoji |
| | `sectionate.odin` | `wrap_sections` — splits HTML at `<h2>` into `<section>` wrappers |
| | `highlight.odin` | Syntax highlighting via tree-sitter. Imports `../treesitter`. |
| | `heading_ids.odin` | `inject_heading_ids` — adds `id` attributes to `<h1>`-`<h6>` from heading text. Slug-based, deduplicated. |
| | `deflists.odin` | `convert_deflists` — pre-cmark pass. Scans for definition list patterns (`term\n\n: definition`) and converts to `<dl><dt><dd>` HTML blocks. Terms and definitions rendered through cmark individually for inline markdown. Consecutive pairs grouped into single `<dl>`. |
| | `toc.odin` | `generate_toc(html, allocator)` — page-level feature (not a pipeline extension). Scans `<h1>`-`<h6>` for IDs (after `inject_heading_ids`), builds nested `<ul>` with `<a href="#id">` links. Called from `load_page` when frontmatter `"toc": true`. Depends on `.HeadingIDs` being enabled. |
| `mustache/` | See [Mustache engine](#mustache-engine) below | Template engine |
| `bench/` | `bench.odin` + `templates/` | Standalone template rendering benchmark. Generates 500 posts + 100 comments, renders with indented partials + inheritance + pipes. `--dump <path>` for output validation, positional arg for iteration count (default 250). |

Icon SVGs live as HTML partials in `layouts/partials/icons/` (home, github, rss, chevron_up, star).

### Data flow

```
thor.json → find_config → init_site (5-step)
  → build_vfs (defaults/layouts → modules → site/layouts, site/assets)
  → site_load_content (scan_content_files + collect_languages + preload_grammars + load_page + url computation + build_menus + warn_all_duplicate_weights)
  → render_site
    → load_partials + get_template (VFS + fallback chain)
    → render_page_html / render_home_html / render_section (3-frame context stack: site, page, ctx)
    → optional minify_html
    → public/
```

## Page struct

```odin
Page :: struct {
    section:     string,      // "" for root, "posts", etc.
    slug:        string,
    layout:      string,      // inferred or frontmatter override
    permalink:   string,      // relative URL path
    url:         string,      // full canonical URL (base_url + permalink)
    title:       string,
    description: string,
    date:        string,
    year:        string,
    weight:      Maybe(int),  // page ordering (nil = unset, defaults to DEFAULT_WEIGHT at comparison time)
    lastmod:     string,
    menus:       map[string]Menu_Entry,  // frontmatter menu assignments
    params:      json.Value,  // per-page params (merged with site params at render time)
    content:     string,      // rendered HTML body
    og:          Open_Graph,
    draft:       bool,
    toc:         string,      // generated table of contents HTML (empty if not requested)
    _is_index:   bool `private`,
}
```
```

No `Page_Type` enum — page type is inferred from section + `_is_index`. Layout is inferred via `infer_layout(section, is_index)`:

- Home (root index): `"home"`
- Section index: `"<section>_index"` (e.g. `"posts_index"`)
- Section page: singularized section (e.g. `"post"`)
- Root page: `"page"`

**Template fallback chain** (in `get_template`): for content pages, `post → page → base`; for section indexes, `posts_index → section_index → page → base`. Fallbacks logged at debug level. Frontmatter `layout` field overrides the inferred value.

## Menus

Menu system in `menus.odin`. `Menu_Entry :: struct {name: string, url: string, weight: int}`. `DEFAULT_WEIGHT = 10`.

### Sources (priority chain, no mixing)

1. **Config menus** (`"menus"` key in `thor.json`) — exclusive. `"menus": {}` = explicit opt-out (no menus). Config entries sorted by weight.
2. **Auto-menus + page frontmatter** — always run together when no config menus:
   - Auto: one entry per section directory + one per root-level non-index page. Alphabetical.
   - Page frontmatter: `"menus": "main"` (string), `["main", "footer"]` (array), or `{"main": {"weight": 30}}` (object with per-menu weight). Merged with auto entries, sorted by weight.

### Weight

All weight fields use `Maybe(int)` — nil means "unset," `some(v)` means explicitly set. This distinguishes `"weight": 10` (explicit) from no weight key (defaults to `DEFAULT_WEIGHT` at comparison time via `.? or_else DEFAULT_WEIGHT`). Eliminates the old `0`-as-sentinel pattern from `json_get_int`.

- `Page.weight: Maybe(int)` — page-level ordering. nil = unset. Affects `sort_pages` (weight primary, date secondary).
- `Menu_Entry.weight: Maybe(int)` — per-menu ordering. nil for auto-generated entries and string/array frontmatter forms. Explicit value from object frontmatter form `{"weight": N}`.
- Effective weight in `merge_page_menus`: per-menu weight if set, else falls back to `page.weight`. Both `Maybe(int)`, so nil propagates naturally — no value-based sentinel check.
- Sorted ascending via `.? or_else DEFAULT_WEIGHT`, name alphabetical for ties.

### Templates

```html
{{#menus.main}}
  <li><a href="{{url}}">{{name}}</a></li>
{{/menus.main}}
```

`Template_Context.menus` resolves above `Page.menus` (frontmatter assignments) on the 3-frame context stack. Accessible as `{{#menus.main}}` or `{{#site.menus.main}}`.

### Duplicate weight warnings

`warn_duplicate_weights` (called from `build_menus` after all menus are sorted) logs a warning when two entries in the same menu have the same explicitly-set weight. Only non-nil weights are checked — nil (unset/default) entries are never flagged, so auto-generated entries don't produce noise. The warning includes the menu name, weight value, and both entry names.

## Config system

Config is split into three structs with a clear 5-step initialization flow:

- **`Flags`** — CLI args only. Parsed once in `main.odin` via `core:flags`, passed to `init_site`. Includes path overrides (`--content`, `--assets`, `--output`, `--layouts`), build-mode toggles (`-drafts`, `-watch`, `-minify`), log level (`-verbose` → Debug, `-quiet` → Warning), and `-ext`/`-no-ext` for markdown extension overrides.
- **`Config_File`** — parsed from `thor.json` via `json.unmarshal_string`. Holds title, paths, `markdown_extensions` (JSON), `params` (JSON), `modules` (JSON array of relative paths), `og` (`Open_Graph` struct for site-level OG defaults).
- **`Site`** — runtime state: arena, pages, modules, VFS, `features: bit_set[Feature]`, `markdown_extensions: bit_set[md.Extension]`, `og: Open_Graph` (resolved site-level OG).

**`Feature` enum** — `Drafts`, `Minify`, `Watch`. Checked with `.Minify in site.features`.

**`markdown.Extension` enum** (in the `markdown` package, not main) — `Emoji`, `Sidenotes`, `Alerts`, `Highlight`, `Sections`, `HeadingIDs`, `DefLists`, `Footnotes`. Default is `md.DEFAULT_EXTENSIONS` (currently `.Emoji, .Sidenotes, .Alerts, .HeadingIDs, .DefLists`). Configurable via:
- `thor.json`: `"markdown_extensions": { "emoji": true, "highlight": false, ... }`
- CLI: `-ext:highlight,sections` (enable) / `-no-ext:emoji` (disable). Comma-separated, case-insensitive.

**`find_config`** — walks up from CWD looking for `thor.json`. Falls back to `./thor.json`.

Config precedence: `CLI flags > thor.json values > hardcoded defaults`.

```json
{
  "title": "...",
  "base_url": "...",
  "modules": ["../path/to/module"],
  "og": {
    "image": "https://example.com/og.png"
  },
  "date": {
    "format": "2 Jan 2006",
    "timezone": "America/New_York"
  },
  "grammars": "~/.config/helix/runtime/grammars/",
  "queries": "/path/to/tree-sitter/queries",
  "markdown_extensions": { "emoji": true, "highlight": false },
  "menus": {
    "main": [
      {"name": "Home", "url": "/", "weight": 1},
      {"name": "About", "url": "/about/"}
    ]
  },
  "params": {
    "social": [
      { "name": "github", "url": "...", "icon": "icons/github" }
    ]
  }
}
```

## VFS (Union File System)

Layered directory resolution for templates and assets: `site layouts/ → module layouts/ → defaults/layouts/`.

```odin
VFS :: struct { files: map[string]VFS_Entry }
VFS_Entry :: struct { fs_path: string, data: []byte }
```

`build_vfs` mounts in reverse precedence (defaults first, site last overwrites). `DEFAULTS_PATH` resolved at compile time via `#directory`, so bundled templates ship inside the binary. Modules configured via `"modules": ["../path"]` in `thor.json` — each module contributes `layouts/` and `assets/` subdirectories.

Three access patterns:
- `vfs_get(vfs, path) -> ([]byte, bool)` — data only (lazy-loaded from disk)
- `vfs_get_entry(vfs, path) -> (VFS_Entry, []byte, bool)` — entry + data (for callers that need `fs_path` for diagnostics)
- `vfs_entry_data(entry) -> ([]byte, bool)` — data from an entry already in hand (avoids redundant map lookup when iterating `vfs.files`)

Content is **not yet in the VFS** — `scan_content_files` still uses direct filesystem reads. (See `TODOS.md`.)

## Open Graph

`Open_Graph` struct in `opengraph.odin` with fields ordered per [ogp.me](https://ogp.me/) spec. `is_article` is `Maybe(bool)` — nil means "unset" (distinguished from explicitly `false`).

**Site-level** (`og_for_site`): starts from `Config_File.og` (user-supplied defaults from `thor.json`), then fills empty fields derivable from `Site`:
- `site_name ← site.title`
- `locale ← "en_US"` (default if unset)

**Page-level** (`og_for_page`): copies site OG, derives page-specific fields, then overlays `Page.og` (from frontmatter):
- `url ← page.url`
- `title ← page.title` (falls back to `site_name` if empty)
- `type ← "article" if !page._is_index else "website"`
- `is_article ← !page._is_index`
- `section ← page.section`
- `published_time / modified_time ← page.date / page.lastmod`
- `description ← page.description`, else `generate_description(generate_summary(body_html))` (scrubbed plain text)

Paths through maps (e.g. `params.*`) are silently allowed — not validated. Templates access via `{{og.url}}`, `{{og.title}}`, `{{#og.is_article}}`, etc.

## Markdown pipeline

Lives in the `markdown` package. Entry point: `md.process(body, ext, file_path)`. All `.html` content files skip the pipeline entirely — body is used as-is.

```
raw markdown
  → md.strip_definitions     (if .Sidenotes || .Footnotes — pre-cmark)
  → md.convert_deflists      (if .DefLists — pre-cmark)
  → cmark markdown_to_html   (Unsafe mode for HTML passthrough)
  → md.expand_emoji          (if .Emoji — post-cmark)
  → md.inject_notes          (if .Sidenotes — post-cmark, sidenote rendering)
  → md.inject_footnotes      (if .Footnotes — post-cmark, standard footnote rendering)
  → md.inject_alerts         (if .Alerts — post-cmark)
  → md.highlight_code        (if .Highlight — post-cmark)
  → md.inject_heading_ids    (if .HeadingIDs — post-cmark, pre-sections)
  → md.wrap_sections         (if .Sections — post-cmark)
```

Each step is gated by `bit_set[md.Extension]`.

## Template system

Templates use Mustache with template inheritance (`{{<base}}` / `{{$block}}`):

```html
<!-- base.html -->
<body>{{> nav}}{{$main}}{{/main}}{{> footer}}</body>

<!-- page.html (content layout) -->
{{<base}}
{{$main}}
<main><article><h1>{{page.title}}</h1>{{&content}}</article></main>
{{/main}}
{{/base}}
```

Data is passed as a single `Template_Context` struct. `render_template` passes a 3-frame context stack `[]any{ctx.site, ctx.page, ctx}` to `mustache.render`, which auto-detects `[]any` and expands each element into a stack frame. Name resolution walks top-to-bottom: `Template_Context` → `Page` → `Site_Context`. Fields not found on the top frame fall through to lower frames.

```odin
Template_Context :: struct {
    site:        Site_Context,   // site-level data (title, description, base_url, params, og)
    menus:       map[string][]Menu_Entry,  // generated menu data (copied from site, resolves above Page.menus)
    now:         string,          // UTC ISO 8601 build timestamp
    date_format: string,          // from site.date.format (thor.json)
    timezone:    ^datetime.TZ_Region,  // for format pipe
    og:          Open_Graph,      // computed per-page OG
    params:      json.Value,      // merged site + page params (resolves above Page.params)
    page:        Page,            // current page
    pages:       [dynamic]Page,   // home page list
    posts:       [dynamic]Page,   // section post list
}
```

`Site_Context` is embedded in `Site` via `using site_context`. Fields like `site.title`, `site.menus`, `site.params` are accessed directly on `Site` through promotion. `Template_Context.menus` is copied from `site.menus` to resolve above `Page.menus` (frontmatter assignments) on the context stack. `Template_Context.params` is set per-page via `merge_params(site.params, page.params)` — site params overlaid with page params. Browser title is handled by the `{{> title}}` partial (not a computed field).

`render_site` pre-parses all partials and the base layout once (via `mustache.parse`), then per-layout templates are cached in `get_template`. Year-based grouping on section index pages is done in the template via `{{#posts | group_by year}}` (see Pipes extension below).

### Pipes extension

Section tags and interpolation tags may transform the resolved value before rendering:

```handlebars
{{#posts | group_by year}}
  {{key}}: {{#items}}{{title}}, {{/items}}
{{/posts}}

<!-- Interpolation pipe: format a date for display -->
<time datetime="{{date}}">{{date | format}}</time>
```

Currently implemented: `group_by <field>` (list → list-of-groups) and `format` (ISO date string → display string like "15 Mar 2026"). The `format` pipe resolves `date_format` (string) and `timezone` (`^datetime.TZ_Region`) from the data context. When `timezone` is non-nil, dates are DST-aware converted before formatting. The `MST` token reflects the active timezone abbreviation (e.g. `"EST"`/`"EDT"`) or the source offset (e.g. `"UTC-04:00"`) when no target tz is configured. TZ data is loaded once by `init_site` via `timezone.region_load` using the site arena allocator, stored on `Site.tz`, and freed when the arena is destroyed. Filter results live in `context.temp_allocator` (render-scoped). See `mustache/EXTENSIONS.md` for syntax details, caps (`MAX_PIPES`, `MAX_PIPE_ARGS`), and the `Group` struct shape.

### Comments

`page.html` includes `{{> comments}}`. The `comments.html` partial self-guards with `{{#og.is_article}}` so it only renders on article pages — no separate `is_post` flag.

## Syntax highlighting

Build-time highlighting via Tree-sitter C FFI. No client-side JavaScript.

- **HTML and CSS grammars** statically linked via Nix (`mkGrammarStaticLib` in `thor/flake.nix`). Always available, no `dlopen`.
- **Other grammars** (bash, odin, nu, etc.) loaded via `dlopen` from `.so` files. Pre-scanned from content code fences and loaded in parallel via `preload_grammars` (one thread per language, `sync.Mutex` on `Grammar_Store.cache`). `Grammar_Store.allocator` is the OS heap (set by `init_persistent` before arena override) so grammars persist across watch-mode rebuilds.
- Grammar and query paths configured via `thor.json` (`grammars`, `queries`). Flow: `thor.json` → `Config_File` → `Site` → `main.odin` sets `treesitter.grammar_dir`/`treesitter.query_dir`. Tilde (`~/`) expanded by `expand_path` in `site.odin`. Paths logged at startup.
- Grammar loading split: `ensure_parser` (parser only, used by minify) vs `load_grammar` (parser + query, used by highlight).
- Capture names mapped to CSS classes: `keyword` → `.hl-keyword`, etc.
- Atom-one-dark color theme in `main.css`.

## Minification

Optional, enabled with `-minify` flag (`.Minify` in `Feature` bit_set).

- **HTML** — tree-sitter parses output, strips comments, removes inter-tag whitespace, preserves `<pre>`/`<code>`/`<textarea>`/`<script>`/`<style>` content. Applied after template rendering.
- **CSS** — tree-sitter parses `.css` files in `assets/`, strips comments, collapses whitespace, trims around `{};:,`. Applied during `copy_assets_dir`.
- Non-CSS files in `assets/` copied verbatim.

## Memory management

- `Site` owns a `mem.Dynamic_Arena`
- `init_site` calls `mem.dynamic_arena_init(&site.arena)` (Odin's default alignment suffices)
- Config loading (flags + JSON) uses the arena allocator explicitly
- `site_allocator(site)` returns the arena allocator for callers
- `destroy_site` frees the arena
- `main.odin` sets `context.logger = log.create_console_logger()` — without this, all `log.*` calls are silently dropped
- `context.allocator` is set to `site_allocator(&site)` in the main loop
- `context.temp_allocator` freed per watch-loop iteration via `defer free_all`

## Spall profiling

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
odin test .                  # main package tests (site, frontmatter)
odin test . -all-packages    # includes mustache specs, lambdas, pipes, diagnostics, markdown tests
```

### Benchmark

```bash
cd thor
odin build bench -o:speed
./bench.bin                    # 250 iterations, prints timing
./bench.bin --dump output.html # render once, write to file for diff validation
./bench.bin 1000               # custom iteration count
```

## Mustache engine

Spec-compliant implementation at `mustache/`. See `mustache/SPEC.md` for the implementation specification, `mustache/EXTENSIONS.md` for non-standard extensions (pipes), and `mustache/diagnostic.odin` for the rust-style error formatter.

### Files

| File | Responsibility |
|---|---|
| `mustache.odin` | Public API (`parse`, `render`, `Template`), parser (`parse_section`), renderer (`render_nodes` with `Indent_State` for partial indentation), template inheritance (`merge_block_overrides`), `delete_template`/`delete_partials`. Pipe support in Variable/Unescaped/Section/Inverted tags. |
| `tokenizer.odin` | Tokenizer (template string → `[]Token`), standalone whitespace detection |
| `data.odin` | Reflection-based data model: `base_value` (peels union/any/nested-any layers), `lookup_in` (structs + maps, handles `Type_Info_Any` value kind in maps), `resolve_name`, `is_truthy`, `any_to_string`, `write_value`, `list_info`, `extract_list_element`, `collect_map_keys` |
| `pipes.odin` | Pipes extension: `Pipe_Op` enum (`.Format`, `.Group_By`), `pipe_op_from_string`/`pipe_op_candidates` (reflection-based enum name lookup), `Pipe_Filter` AST (with `op_pos` for diagnostics), `parse_pipeline` (tracks byte offsets via `strings.index`), `apply_pipeline`, `apply_filter` (exhaustive enum switch), `apply_group_by`, `apply_format`. Misspelled pipe op suggestions via `suggest_correction`. Stored on `Node.filters`; render-scoped results in temp allocator. |
| `diagnostic.odin` | Rust-style error formatter: `format_error` (multi-line context, ANSI colors via `core:terminal/ansi`, `colorize` param), `format_render_error` (formats `Error`), `line_col`, `line_text`, `context_extent`, `count_lines`, `digit_count`, `should_colorize`. |
| `suggest.odin` | Strict-warning helpers: `validate_key_path` (walks dotted path, crosses maps silently), `suggest_correction` (Levenshtein via `core:strings/levenshtein_distance`), `collect_struct_keys` (via reflection, recurses into `using`), `struct_has_field` (distinguishes missing field from nil value — needed for `Maybe(bool)`), `collect_partial_names`, `collect_block_names`. |
| `spec_test.odin` | JSON spec test runner — loads `spec/specs/*.json`, runs each test case. Uses `log.nil_logger()` to suppress expected warnings. |
| `pipes_test.odin` | Pipe filter tests (`group_by` + `format`) |
| `diagnostic_test.odin` | Golden-output tests for `format_error` (multi-line context, edge cases, alignment, caret position, hint) + parser error message brace-escaping |
| `suggest_test.odin` | Tests for `validate_key_path`, `suggest_correction`, `struct_has_field` with `Maybe(bool)` and `using`-promoted fields |

### Architecture

```
parse(source, path) → tokenize → trim_standalone_whitespace → parse_section → Template
render(tmpl, data, partials) → render_nodes (walks flat node array against context stack) → string
```

- **Two-phase API**: `parse()` produces a reusable `Template`, `render()` walks it against data. Templates parsed once, rendered many times.
- **Flat `[dynamic]Node` array** with `children: []Node` slices (pre-order layout; slices point into the backing array). Each `Node` carries `pos: int` (byte offset into source) for diagnostics.
- **`Template`** carries `source` and `path` — used by diagnostics to show file location and source context.
- **Context stack**: `^[dynamic]any` with `append`/`pop` for section push/pop.
- **`render_nodes` takes `Template` by value** (not `^Template`) — Odin's calling convention promotes to pointer when efficient. Eliminates "local copy" patterns at call sites.
- **`Block_Override.source: Template`** — carries the template that defined the override, so warnings inside block overrides point at the correct file.
- **`base_value`** peels Named/Distinct/Union layers (including `json.Value`). Also unwraps nested `any`-of-`any` (which occurs when `map[string]any` values are read via runtime map internals).
- **`lookup_in`** resolves keys on structs (via `reflect.struct_field_value_by_name` with `allow_using = true`) and maps. Detects `Type_Info_Any` value kind in maps and reads the inner any directly to avoid double-wrap.
- **Template inheritance**: `{{<parent}}` loads parent from partials, `{{$block}}` defines overridable sections. `merge_block_overrides` propagates overrides through multi-level chains.
- **Dynamic partial names**: `{{>*key}}` resolves partial name from data context at render time.
- **Render-time partial indentation**: `Indent_State` threads `at_line_start` through `render_nodes` so partial indent is applied at render time (via `write_indented` on Text nodes) instead of reparsing the partial's source. `render_template` writes initial indent, creates state, calls `render_nodes`. Data-injected newlines don't pick up indent (Variables don't update `at_line_start`).

### Diagnostics

Rust-style error messages with multi-line source context, caret underlines, and Levenshtein suggestions. ANSI colors via `core:terminal/ansi`, gated on `should_colorize()` (TTY detection on stderr).

**Error types**: `Error_Body{msg, pos, kind, source, path, span, hint}` where `kind` is `Error_Kind.Syntax` (parse-time) or `Error_Kind.Data` (render-time). `source`/`path` carry the template the error originated in (set by `tag_error` — enables correct file/line for errors inside partials). `span` controls caret underline width (used by pipe op diagnostics). `hint` carries "did you mean?" suggestions. `Error` is a single-variant union wrapping `Error_Body` (nilable for `!= nil` / `or_return`).

**Error deduplication**: `render_template` takes `seen: ^map[string]bool`. Duplicate errors (same formatted diagnostic) are suppressed across page renders within a single build.

**Partial source tracking**: `tag_error(err, current)` stamps render-time errors with `current.source`/`current.path` at the 4 `apply_pipeline` call sites in `render_nodes`. Ensures errors inside partials point at the partial file, not the top-level template.

**Strict-by-default warnings** — `render_nodes` emits `log.warnf` diagnostics for:
- Unknown keys in `{{k}}`, `{{{k}}}`, `{{#k}}`, `{{^k}}` (via `validate_key_path` + `suggest_correction`)
- Missing partials (`{{> name}}` not in partials map)
- Missing parent templates (`{{<name}}` not in partials map)
- Unmatched block overrides (`{{$name}}` doesn't match any block in parent template)

**Exceptions** (no warning):
- `{{.}}` and dot-prefixed names (current context)
- Paths that cross a map (e.g., `params.*`) — validated for typos via Levenshtein: close matches warn with a suggestion, genuinely absent keys are suppressed silently
- `Maybe(bool)` fields with nil value (field exists, value is nil — distinguished via `struct_has_field`)
- Found fields whose value is nil/empty (e.g., nil `json.Value` union) — the field exists, looking up sub-keys is valid "not found" behavior

**Block override source tracking**: `Block_Override.source: Template` ensures warnings inside block overrides point at the override's source file (e.g., `page.html`), not the parent template (`base.html`).

### Pipes

`{{key | op args…}}` for interpolation, `{{#key | op args…}}…{{/key}}` for sections. Stored as `[dynamic; MAX_PIPES]Pipe_Filter` on each `Node`. Applied in the renderer via `apply_pipeline` before truthiness/interpolation. Implemented filters:

- `group_by <field>` — list → `[dynamic]Group` where `Group{key, items}`
- `format` — ISO 8601 date string → display string (e.g., "15 Mar 2026")

See `mustache/EXTENSIONS.md`.

### Not implemented

- Set delimiters (`{{= =}}`, `delimiters.json`)
- Partial invocation stack in diagnostics (warnings inside partials point at the partial file but don't show the `{{> name}}` invocation site — see TODOS.md)

## Known limitations

- CSS/JS cache busting uses manual `?v=N` query params instead of content hashing.
- Tree-sitter grammar/query paths must be configured manually via `thor.json` (`grammars`, `queries`) — no auto-discovery. HTML/CSS are statically linked.
- `map[string]any` only works through `lookup_in`'s special-case handling; thor otherwise uses structs.
- `format_f64` in mustache brute-forces shortest float representation.
- Content directory not mounted in VFS (modules can ship templates/assets but not content packs yet).
- Per-page params rendering is incomplete — `merge_params` produces correct data, but `base_value` may return nil for `json.Value` fields accessed through the `[]any` context stack via reflection in some cases. Warning suppression masks this; actual rendering may not work for all param values.
- Lambda support removed. Mustache lambdas (`proc() -> string` in data context) are not supported. Pipes cover data transformation.

## Design decisions

You may never, *ever* remove `TODO:` or `FIXME:` comments. Those are for humans, not machines.
See `HUGO.md` for analysis of why thor doesn't need Hugo's shortcode context isolation.
See `mustache/SPEC.md` for the original implementation specification.
See `mustache/EXTENSIONS.md` for non-standard extensions (pipes).
See `DIAGNOSTICS.md` for the two-tier diagnostic system design.
See `mustache/TOKENIZERS.md` for tokenizer architecture comparison (Go, Liquid, Thor).

## Odin language facts

These are things that are easy to get wrong:

- **Proc arguments are immutable.** You cannot assign to a parameter directly. To get a mutable copy, shadow it: `x := x`. If you need to modify the source, pass a pointer `^x`.
- **`for` each loops use `item, idx` order**, not `idx, item`. Correct: `for item, idx in arr`. Wrong: `for idx, item in arr`.
- **`make([dynamic]T, n, allocator)` sets capacity, not length.** To get length=0 with capacity=n, use `make([dynamic]T, 0, n, allocator)`. Using `make([dynamic]T, n, allocator)` creates `len=n` with `n` zero-initialized elements.
- `#partial switch` is usually a code smell. prefer a `case all, extra, types:` branch.
- you don't usually need to create arena allocators in tests, instead use context.temp_allocator if you want to simplify cleanup.
- you don't need to manually set up a tracking allocator in tests. the context.allocator will warn you about leaks.
- **`Maybe(T)` unwrap syntax:** `value.? or_else default`. Not `value or_else default` — `or_else` works on the `?T` returned by `.?`, not on `Maybe(T)` directly.
- **`Maybe(T)` equality:** `a == b` works directly between two `Maybe(T)` values (nil == nil → true, some(5) == some(5) → true, nil == some(5) → false). Also `a == 5` works (int coerces to `Maybe(int)`).
- **File logger in tests:** `log.create_file_logger(&f)` + `context.logger = logger` captures log output. Must be set inline in the test proc (not via a helper proc) for context propagation. Clean up with `log.destroy_file_logger(logger)` then `os.read_entire_file_from_path` to verify output.
- **`fmt.sbprintf` writes directly to a `strings.Builder`.** Prefer `fmt.sbprintf(&sb, fmt, args...)` over `fmt.aprintf(fmt, args...)` + `defer delete` + `strings.write_string`. The `aprintf` pattern allocates an intermediate string, requires manual cleanup, and queues a `defer delete` per loop iteration. `sbprintf` avoids all of this.

## TODO

See `TODOS.md` for the full list.
