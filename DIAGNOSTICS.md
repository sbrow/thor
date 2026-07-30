# Diagnostics

Thor has two diagnostic tiers. This document explains why, and when to use each.

## Tier 1: Rust-style rich diagnostics (mustache engine)

`mustache/diagnostic.odin` implements multi-line source context, caret underlines, ANSI colors (gated on TTY detection), and Levenshtein suggestions. Used exclusively by the mustache engine for template errors:

- Unknown keys in `{{k}}`, `{{{k}}}`, `{{#k}}`, `{{^k}}`
- Missing partials (`{{> name}}`)
- Missing parent templates (`{{<name}}`)
- Unmatched block overrides (`{{$name}}`)
- Parse-time syntax errors

These benefit from rich diagnostics because **exact source location matters** — templates have complex syntax, and the user often doesn't know *where* the problem is. The diagnostic system operates on `Template.source` with byte offsets, producing output like:

```
error: unknown key 'titel' in {{page.titel}}
  --> layouts/page.html:12:22
   |
12 |   <h1>{{page.titel}}</h1>
   |                  ^^^^^
   |
   = hint: did you mean 'title'?
```

## Tier 2: Simple log warnings (content and runtime)

Everything outside the mustache engine uses `log.warnf` — flat one-line messages via `core:log`:

- Missing frontmatter dates (fallback to file mtime)
- Duplicate menu weights
- Non-numeric weight values in frontmatter
- Tree-sitter highlight errors
- Menu system issues (mixing config/frontmatter menus, etc.)

These are simple, actionable, and cross-file. The problem isn't *location* — it's that two files disagree, or a value is missing. A caret pointing at one file doesn't help; the message already communicates what to fix:

```
[WARN] --- [menus.odin:290:warn_duplicate_weights()] menus('main'):'Ideas' and 'Stuff' share the same weight (11).
```

## Why not use rich diagnostics everywhere?

Rust's diagnostic model is built for a single compilation unit with full AST/IR data. Three obstacles prevent reusing it for content warnings:

1. **Source tracking**: The mustache diagnostic system operates on `Template.source` (byte offsets into template strings). Content warnings come from frontmatter in markdown files — different source, different parser, no position tracking. Reusing the system would require building a parallel position-tracking infrastructure for frontmatter.

2. **Cross-file context**: Rust diagnostics point at one location. Weight duplicates are a relationship between two files. Rich diagnostics would need to show *both* file locations, which is more infrastructure for marginal value.

3. **Diminishing returns**: Rust diagnostics shine for syntax/type errors where the user doesn't understand the failure. Content warnings are already self-explanatory — "these two pages share weight 11" doesn't need a caret to be actionable.

## When to upgrade a Tier 2 warning to Tier 1

If a warning's usefulness would significantly improve from showing exact source location (e.g., a frontmatter syntax error where the user needs to see *which line* is malformed), consider extending the diagnostic system to frontmatter. This would require:

1. Position tracking in `frontmatter.odin` (store byte offsets for each parsed field)
2. A `format_frontmatter_error` proc modeled on `format_render_error`
3. File path propagation through the page loading pipeline

This is not currently planned — see `TODOS.md`.
