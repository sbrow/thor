# Hugo vs Thor: Why Thor Doesn't Need Shortcode Context Isolation

## Hugo's Shortcode Isolation

Hugo strictly separates shortcode context from layout template context. Shortcodes run during markdown rendering, before layouts. They get a limited context (`.Page`, `.Site`, `.Params`), not the full layout rendering state.

### Why Hugo does this

1. **Circular dependencies** — Hugo shortcodes output into `.Content`. Layouts read `.Content` and compute derived properties (`.TableOfContents`, `.WordCount`, `.ReadingTime`). If shortcodes could access these computed properties, you'd get circular dependencies (shortcode output → computed property → shortcode reads it).

2. **Multiple layouts/themes** — Hugo supports user-selectable themes and multiple layouts per section type. A shortcode must produce identical output regardless of which layout renders it. Isolating context guarantees portability.

3. **Shared mutable page object** — Hugo builds a rich `Page` object that both shortcodes and layouts access. Context isolation prevents shortcodes from mutating layout-visible state.

4. **Security** — Shortcodes live in content files (potentially user-authored). Full template access would let content authors inject arbitrary logic, access sensitive config, or break site structure.

5. **Caching** — Hugo caches shortcode output independently. Predictable context = predictable cache behavior.

## Why this doesn't apply to thor

- **No computed page properties** — The content Mustache pass runs on raw markdown (before cmark). The layout Mustache pass runs on finished HTML (after cmark). There's no shared `.Content` object or derived properties. The two passes are at different pipeline stages with no shared mutable state.

- **Single layout set** — Thor has one set of templates (`base.html` + page templates). No theme switching, no multiple layout variants per section. Portability across layouts isn't a concern.

- **Explicit data passing** — Each `mustache.render` call receives its own data struct. Content pass gets frontmatter + params. Layout pass gets page data + site config. No shared mutable object between them.

- **Single author** — Content is authored by the site owner. No untrusted user-generated content.

- **No caching** — Thor rebuilds from scratch every time. No cache invalidation concerns.

## Thor's approach

Thor runs Mustache on content **before** cmark as a pre-processing step, then runs Mustache on layout templates **after** cmark as a post-processing step. These are two independent `mustache.render` calls:

```
content (markdown)
  → mustache.render(content, content_data, partials)   ← content pass
  → cmark markdown_to_html
  → inject_sidenotes / inject_alerts / highlight_code
  → mustache.render_in_layout(template, page_data, layout, partials)  ← layout pass
  → final HTML
```

The content pass can use Mustache variables, partials (`{{> ./file}}`), sections, and conditionals freely. The layout pass wraps the rendered content in the page chrome. They share nothing except the data we explicitly choose to pass.

## When this WOULD matter for thor

If thor ever adds:
- Computed page properties (table of contents, reading time, word count)
- Multiple selectable themes/layouts
- User-generated content / multi-author support
- Partial template caching

...then context isolation between the content and layout passes would become relevant. Until then, it's unnecessary complexity.
