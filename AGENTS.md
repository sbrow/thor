# Thor — Odin Static Site Generator

Thor is a static site generator written in [Odin](https://odin-lang.org), replacing Hugo for the `sbrow.github.io` blog. It lives at `./thor/` as a git subtree with its own `flake.nix`.

## Architecture

```
thor.json          ← site config (title, base_url, author, params)
content/           ← markdown and HTML content files
layouts/           ← Mustache templates + partials
assets/            ← CSS (TailwindCSS source) and JS
public/            ← build output (generated)
```

### Source files

| File | Responsibility |
|---|---|
| `main.odin` | Entry point. Calls `init_site`, `walk_content`, `render_site` |
| `site.odin` | `Site` struct (config + arena), `init_site`, `load_site_config`, `site_merge`, `site_allocator`, `destroy_site` |
| `frontmatter.odin` | JSON frontmatter parser (`{ }` delimited) |
| `content.odin` | `Page` struct, content walker, page loader, cmark integration, footnote/alert/emoji pipeline |
| `footnotes.odin` | Footnote definition stripping (pre-cmark) + sidenote injection (post-cmark) |
| `alerts.odin` | GitHub alert post-processor (`> [!CAUTION]` → styled blockquote) |
| `emoji.odin` | Emoji shortcode expander (`:shrug:` → `¯\_(ツ)_/¯`) |
| `render.odin` | Mustache template rendering, all page types, RSS, sitemap, robots.txt, `load_partials` recursive scan |
| `feed.odin` | RSS feed + sitemap XML generation |
| `mustache/` | Vendored [odin-mustache](https://github.com/benjamindblock/odin-mustache) library |

Icon SVGs live as HTML partials in `layouts/partials/icons/` (home, github, rss, chevron_up, star).

### Data flow

```
thor.json → init_site → Site (config + Dynamic_Arena)
                            ↓
content/ → walk_content → []Page (with body_html from cmark pipeline)
                            ↓
layouts/*.html → render_site (Mustache render_in_layout) → public/
```

### Config system

`Site` has `params: json.Value` for arbitrary user-defined data from `thor.json`. Social links and other template-only data live under `"params"`:

```json
{
  "title": "...",
  "base_url": "...",
  "author": "...",
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
  → inject_sidenotes      (post-cmark: [^id] → <label><input><span> markup)
  → inject_alerts         (post-cmark: [!TYPE] blockquotes → styled alerts)
```

`.html` content files skip cmark entirely — body is used as-is.

### Memory management

- `Site` owns a `mem.Dynamic_Arena`
- `init_site` calls `mem.dynamic_arena_init(&site.arena, alignment = 64)` — the 64-byte alignment is required by Odin's map runtime (`MAP_CACHE_LINE_SIZE`)
- Config loading (flags + JSON) uses the arena allocator explicitly
- `site_allocator(site)` returns the arena allocator for callers
- `destroy_site` frees the arena
- **Not yet wired:** `context.allocator` is not set to the arena in `main.odin`, so rendering and content processing still use the heap allocator

## Building

### Local development

```bash
nix develop
# From blog root:
odin run ./thor -- -drafts
tailwindcss --input assets/css/main.css --output public/css/main.css --minify
cp assets/js/main.js public/js/main.js
caddy run  # serves public/ on blog.localhost
```

### Production build

```bash
nix build  # runs thor + tailwindcss + cp js, outputs to ./result/
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

3. **Inline partial rendering** — replaced `template_insert_partial` (which injected tokens into the main token list, breaking section iteration) with `template_render_partial` (which lexes the partial, temporarily swaps `tmpl.lexer`, and recursively processes via `template_process_tokens`). Fixes partials inside sections.

4. **Dynamic Names** — `{{>*key}}` support. When a partial token value starts with `*`, the remaining key is resolved from the data context stack, and the resolved string is used as the partial name. Enables per-item partial selection inside sections (e.g., `{{>* icon}}` resolves `icon` from each social link).

Extracted `template_process_tokens` from `template_eat_tokens` to separate ROOT initialization + skip pass from the core token loop, allowing partials to reuse the loop.

## Known limitations

- cmark allocates via C malloc, not the arena. HTML output leaks until process exit.
- CSS/JS cache busting uses manual `?v=N` query params instead of content hashing.
- The `shrug` emoji has a backslash that may not display correctly.
- `json.Value` params require 64-byte aligned arena (workaround for `dynamic_arena_allocator_proc` ignoring per-allocation alignment).

## TODO

See `TODOS.md` for the full list.
