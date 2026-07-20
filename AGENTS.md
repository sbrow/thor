# Thor — Odin Static Site Generator

Thor is a static site generator written in [Odin](https://odin-lang.org), replacing Hugo for the `sbrow.github.io` blog. It lives at `./thor/` as a git subtree with its own `flake.nix`.

## Architecture

```
thor.json          ← site config (title, base_url, author, params, modules)
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
├── mustache/           # Template engine with lambdas + pipe filters
├── content.odin        # Page struct, scan_content, load_page
├── render.odin         # Template rendering, data structs, RSS, sitemap
├── site.odin           # Config (Flags, Config_File, Site), init_site
├── minify.odin         # HTML/CSS minification (imports treesitter)
├── feed.odin           # RSS + sitemap generation
├── vfs.odin            # Union file system (defaults → modules → site)
├── assets.odin         # VFS-based asset copying
├── opengraph.odin      # Open_Graph struct + og_init/og_for_page
├── frontmatter.odin    # JSON frontmatter parser
├── defaults.odin       # DEFAULTS_PATH constant (#directory)
├── main.odin           # Entry point
└── defaults/layouts/   # Bundled default templates
```

### Source files (main package)

| File | Responsibility |
|---|---|
| `main.odin` | Entry point. Sets `context.logger`, calls `init_site`, `build_vfs`, `site_load_content`, `render_site`. Optional Spall profiling via `SPALL` config flag. |
| `site.odin` | `Flags` (CLI), `Config_File` (thor.json), `Site` (runtime state + arena + VFS + pages + modules). `Feature` enum. 5-step `init_site`. Imports `md "markdown"` for `Extension` enum. |
| `content.odin` | `Page` struct, `scan_content` (section-aware walk that handles leaf bundles), `load_page`, `infer_layout`. Calls `md.process()` for the markdown pipeline. |
| `render.odin` | Template rendering: `render_site`, `render_page_html`, `render_home_html`, `render_section`. Data structs (`Base_Data`, `Page_Data`, `Home_Data`, `Section_Data`). VFS-based template loading with fallback chain (`get_template`). |
| `minify.odin` | HTML/CSS minification via tree-sitter. Imports `ts "treesitter"`. |
| `feed.odin` | RSS feed + sitemap XML. Uses `page.url` for canonical URLs. |
| `vfs.odin` | Union file system: `VFS`, `build_vfs`, `mount_dir`, `mount_subdir`, `mount_recursive`, `vfs_get`. Layers defaults → modules → site. |
| `assets.odin` | `copy_assets_dir` — iterates VFS entries with `assets/` prefix, minifies CSS, copies verbatim or via `os.copy_file`. |
| `opengraph.odin` | `Open_Graph` struct (fields ordered per OGP spec). `og_init(site)` for site defaults, `og_for_page(site, page, base)` for page-specific OG data. |
| `frontmatter.odin` | JSON frontmatter parser (`{ }` delimited). Supports `layout` field for template override. |
| `defaults.odin` | `DEFAULTS_PATH` constant, resolved at compile time via `#directory` so bundled templates ship in the binary. |

### Subpackages

| Package | Files | Responsibility |
|---|---|---|
| `treesitter/` | `treesitter.odin` | FFI types (`Parser`, `Node`, `Query`, etc.), `@(link_prefix="ts_")` foreign bindings, grammar management (`ensure_parser`, `load_grammar`, `grammar_cache`), statically-linked HTML/CSS grammars |
| `markdown/` | `markdown.odin` | `Extension` enum, `DEFAULT_EXTENSIONS`, `process(body, ext, file_path)` — full pipeline, `parse_extension_list`, `apply_extension_config` |
| | `footnotes.odin` | `strip_definitions` (pre-cmark), `inject_notes` (post-cmark) |
| | `alerts.odin` | `inject_alerts` — GitHub alert blocks (`> [!NOTE]`) → styled blockquotes with semantic class names (`alert-note` etc.) |
| | `emoji.odin` | `expand_emoji` — `:shortcode:` → unicode emoji |
| | `sectionate.odin` | `wrap_sections` — splits HTML at `<h2>` into `<section>` wrappers |
| | `highlight.odin` | Syntax highlighting via tree-sitter. Imports `../treesitter`. |
| `mustache/` | See [Mustache engine](#mustache-engine) below | Template engine |

Icon SVGs live as HTML partials in `layouts/partials/icons/` (home, github, rss, chevron_up, star).

### Data flow

```
thor.json → find_config → init_site (5-step)
  → build_vfs (defaults/layouts → modules → site/layouts, site/assets)
  → site_load_content (scan_content + url computation)
  → render_site
    → load_partials + get_template (VFS + fallback chain)
    → render_page_html / render_home_html / render_section
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
    menu:        string,
    body_html:   string,
    draft:       bool,
    is_starred:  bool,
    _is_index:   bool `private`,
}
```

No `Page_Type` enum — page type is inferred from section + `_is_index`. Layout is inferred via `infer_layout(section, is_index)`:

- Home (root index): `"home"`
- Section index: `"<section>_index"` (e.g. `"posts_index"`)
- Section page: singularized section (e.g. `"post"`)
- Root page: `"page"`

**Template fallback chain** (in `get_template`): for content pages, `post → page → base`; for section indexes, `posts_index → section_index → page → base`. Fallbacks logged at debug level. Frontmatter `layout` field overrides the inferred value.

## Config system

Config is split into three structs with a clear 5-step initialization flow:

- **`Flags`** — CLI args only. Parsed by `core:flags`. Includes path overrides (`--content`, `--assets`, `--output`, `--layouts`), build-mode toggles (`-drafts`, `-watch`, `-minify`), and `-ext`/`-no-ext` for markdown extension overrides.
- **`Config_File`** — parsed from `thor.json` via `json.unmarshal_string`. Holds title, paths, `markdown_extensions` (JSON), `params` (JSON), `modules` (JSON array of relative paths).
- **`Site`** — runtime state: arena, pages, modules, VFS, `features: bit_set[Feature]`, `markdown_extensions: bit_set[md.Extension]`.

**`Feature` enum** — `Drafts`, `Minify`, `Watch`. Checked with `.Minify in site.features`.

**`markdown.Extension` enum** (in the `markdown` package, not main) — `Emoji`, `Sidenotes`, `Alerts`, `Highlight`, `Sections`. Default is `md.DEFAULT_EXTENSIONS` (currently `.Emoji, .Sidenotes, .Alerts`). Configurable via:
- `thor.json`: `"markdown_extensions": { "emoji": true, "highlight": false, ... }`
- CLI: `-ext:highlight,sections` (enable) / `-no-ext:emoji` (disable). Comma-separated, case-insensitive.

**`find_config`** — walks up from CWD looking for `thor.json`. Falls back to `./thor.json`.

Config precedence: `CLI flags > thor.json values > hardcoded defaults`.

```json
{
  "title": "...",
  "base_url": "...",
  "author": "...",
  "modules": ["../path/to/module"],
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

## VFS (Union File System)

Layered directory resolution for templates and assets: `site layouts/ → module layouts/ → defaults/layouts/`.

```odin
VFS :: struct { files: map[string]VFS_Entry }
VFS_Entry :: struct { fs_path: string, data: []byte }
```

`build_vfs` mounts in reverse precedence (defaults first, site last overwrites). `DEFAULTS_PATH` resolved at compile time via `#directory`, so bundled templates ship inside the binary. Modules configured via `"modules": ["../path"]` in `thor.json` — each module contributes `layouts/` and `assets/` subdirectories. `vfs_get` lazily reads file contents on first access.

Content is **not yet in the VFS** — `scan_content` still uses direct filesystem reads. (See `TODOS.md`.)

## Open Graph

`Open_Graph` struct in `opengraph.odin` with fields ordered per [ogp.me](https://ogp.me/) spec. Site defaults set via `og_init(site)` (site_name, description, default image, locale). Page-specific fields via `og_for_page(site, page, base)` (copies base, overrides url/title/type/is_article/section/published_time). Templates access via `{{og.url}}`, `{{og.title}}`, `{{#og.is_article}}`, etc.

## Markdown pipeline

Lives in the `markdown` package. Entry point: `md.process(body, ext, file_path)`. All `.html` content files skip the pipeline entirely — body is used as-is.

```
raw markdown
  → md.strip_definitions     (if .Sidenotes — pre-cmark)
  → cmark markdown_to_html   (Unsafe mode for HTML passthrough)
  → md.expand_emoji          (if .Emoji — post-cmark)
  → md.inject_notes          (if .Sidenotes — post-cmark)
  → md.inject_alerts         (if .Alerts — post-cmark)
  → md.highlight_code        (if .Highlight — post-cmark)
  → md.wrap_sections         (if .Sections — post-cmark)
```

Each step is gated by `bit_set[md.Extension]`.

## Template system

Templates use Mustache with template inheritance (`{{<base}}` / `{{$block}}`):

```html
<!-- base.html -->
<body>{{> nav}}{{$content}}{{/content}}{{> footer}}</body>

<!-- page.html (content layout) -->
{{<base}}
{{$content}}
<main><article><h1>{{page_title}}</h1>{{&body}}</article></main>
{{/content}}
{{/base}}
```

Data is passed as **typed structs** (not `map[string]any`). Mustache resolves struct fields via Odin reflection, including `using`-embedded fields. Date presence is checked via string truthiness (`{{#date_iso}}`) — no separate `has_date` bool needed.

```odin
Base_Data :: struct {
    now:    datetime.DateTime,
    author: string,
    params: json.Value,
    body:   string,
    title:  string,
    og:     Open_Graph,
}
Page_Data :: struct {
    using base:   Base_Data,  // fields promoted via reflection fallback
    page_title:   string,
    date_iso:     string,
    date_display: string,
}
Home_Data :: struct {
    using base: Base_Data,
    pages:      [dynamic]Page_Context,
}
Section_Data :: struct {
    using base: Base_Data,
    page_title: string,
    posts:      [dynamic]Page_Context,  // flat list; year grouping done in template via pipe
}
```

`render_site` pre-parses all partials and the base layout once (via `mustache.parse`), then per-layout templates are cached in `get_template`. Year-based grouping on section index pages is done in the template via `{{#posts | group_by year}}` (see Pipes extension below) — there is no `Year_Section` Go-side struct.

### Pipes extension

Section tags may transform the resolved value before iteration:

```handlebars
{{#posts | group_by year}}
  {{key}}: {{#items}}{{title}}, {{/items}}
{{/posts}}
```

Currently only `group_by <field>` is implemented. Filter results live in `context.temp_allocator` (render-scoped). See `mustache/EXTENSIONS.md` for syntax details, caps (`MAX_PIPES`, `MAX_PIPE_ARGS`), and the `Group` struct shape.

### Comments

`page.html` includes `{{> comments}}`. The `comments.html` partial self-guards with `{{#og.is_article}}` so it only renders on article pages — no separate `is_post` flag.

## Syntax highlighting

Build-time highlighting via Tree-sitter C FFI. No client-side JavaScript.

- **HTML and CSS grammars** statically linked via Nix (`mkGrammarStaticLib` in `thor/flake.nix`). Always available, no `dlopen`.
- **Other grammars** (bash, odin, nu, etc.) loaded via `dlopen` from Helix's compiled `.so` files.
- Highlight queries (`.scm`) loaded from Helix's runtime directory.
- Paths hardcoded in `treesitter/treesitter.odin` (`GRAPHS_PATH`, `QUERIES_PATH`) — Nix store paths, Helix-version-dependent. (See `TODOS.md`.)
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
odin test . -all-packages    # includes mustache specs, lambdas, pipes, markdown tests
```

## Mustache engine

Spec-compliant implementation at `mustache/`. See `mustache/SPEC.md` for the implementation specification and `mustache/EXTENSIONS.md` for non-standard extensions (pipes).

### Files

| File | Responsibility |
|---|---|
| `mustache.odin` | Public API (`parse`, `render`, `Template`), parser (`parse_section` with allocator threading), renderer (`render_nodes`), template inheritance (`merge_block_overrides`), `delete_template`/`delete_partials` |
| `tokenizer.odin` | Tokenizer (template string → `[]Token`), standalone whitespace detection |
| `data.odin` | Reflection-based data model: `base_value` (peels union/any/nested-any layers), `lookup_in` (structs + maps, handles `Type_Info_Any` value kind in maps), `resolve_name`, `is_truthy`, `any_to_string`, `list_info`, `extract_list_element` (unwraps `[dynamic]any` element types so downstream lookups see the real value), `call_interp_lambda`/`call_section_lambda` |
| `pipes.odin` | Pipes extension: `Pipe_Filter` AST, `parse_pipeline`, `apply_pipeline`, `apply_filter` (switch dispatch), `apply_group_by`. Stored on `Node.filters`; render-scoped results in temp allocator. |
| `spec_test.odin` | JSON spec test runner — loads `spec/specs/*.json`, runs each test case |
| `lambda_test.odin` | Spec lambda tests |
| `pipes_test.odin` | Pipe filter tests |

### Architecture

```
parse(source) → tokenize → trim_standalone_whitespace → parse_section → Template
render(tmpl, data, partials) → render_nodes (walks flat node array against context stack) → string
```

- **Two-phase API**: `parse()` produces a reusable `Template`, `render()` walks it against data. Templates parsed once, rendered many times.
- **Flat `[dynamic]Node` array** with `first_child`/`child_count` indices — pre-order layout.
- **Context stack**: `^[dynamic]any` with `append`/`pop` for section push/pop.
- **`base_value`** peels Named/Distinct/Union layers (including `json.Value`). Also unwraps nested `any`-of-`any` (which occurs when `map[string]any` values are read via runtime map internals).
- **`lookup_in`** resolves keys on structs (via `reflect.struct_field_value_by_name` with `allow_using = true`) and maps. Detects `Type_Info_Any` value kind in maps and reads the inner any directly to avoid double-wrap.
- **Template inheritance**: `{{<parent}}` loads parent from partials, `{{$block}}` defines overridable sections. `merge_block_overrides` propagates overrides through multi-level chains.
- **Dynamic partial names**: `{{>*key}}` resolves partial name from data context at render time.

### Lambdas

Spec-compliant. Stored as `any` values in the data context.

- **Interpolation lambdas**: `proc() -> string`, `proc() -> int`, `proc() -> bool` — called via `call_interp_lambda`, result stringified and escaped.
- **Section lambdas**: `proc(string) -> string`, `proc(string) -> int`, `proc(string) -> bool` — called via `call_section_lambda` with the raw section text (`node.content`). String result is re-parsed as mustache and rendered against the current context stack.

### Pipes

`{{#key | op args…}}…{{/key}}`. Stored as `[dynamic; MAX_PIPES]Pipe_Filter` on each `Node` (fixed-cap inline storage, no per-tag heap allocation at parse time). Applied in the renderer via `apply_pipeline` before truthiness check. Currently only `group_by <field>` is implemented (returns `[dynamic]Group` where `Group{key, items}`). See `mustache/EXTENSIONS.md`.

### Not implemented

- Set delimiters (`{{= =}}`, `delimiters.json`)

## Known limitations

- cmark allocates via C malloc, not the arena. HTML output leaks until process exit (problematic in watch mode — see `TODOS.md`).
- CSS/JS cache busting uses manual `?v=N` query params instead of content hashing.
- Tree-sitter grammar/query paths for dynamic grammars hardcoded in `treesitter/treesitter.odin` (Nix store hashes, Helix-version-dependent). HTML/CSS are statically linked.
- `map[string]any` only works through `lookup_in`'s special-case handling; thor otherwise uses structs.
- `format_f64` in mustache brute-forces shortest float representation.
- Content directory not mounted in VFS (modules can ship templates/assets but not content packs yet).

## Design decisions

You may never, *ever* remove `TODO:` or `FIXME:` comments. Those are for humans, not machines.
See `HUGO.md` for analysis of why thor doesn't need Hugo's shortcode context isolation.
See `mustache/PARTIAL_INDENT.md` for whitespace handling analysis.
See `mustache/SPEC.md` for the original implementation specification.
See `mustache/EXTENSIONS.md` for non-standard extensions (pipes).

## TODO

See `TODOS.md` for the full list.
