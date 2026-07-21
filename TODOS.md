## Performance

- [ ] See if we can disable bounds checks in `write_indented` and elsewhere.
- [ ] Instead of loading the site fresh each time in watch mode, create a
      `reload_site` proc, that just updates changed resources.
- [ ] Only publish referenced assets.
- [ ] Split `load_page` into frontmatter-parse + body-process phases so draft pages can skip the markdown pipeline entirely
- [ ] Use spall to find ways to reduce run time.
- [ ] Consider using `#soa` for Page lists.

## Memory Management

- [ ] Not sure whether to use temp allocator or site_allocator in opengraph.odin.
- [ ] Not sure whether to use temp allocator or site_allocator in `site_load_content`.
- [ ] Might not need to allocate in `strip_html_tags`

## Markdown
- [ ] Add overloads for every extension - accept ^strings.Builder.
- [ ] Add conventional (Hugo style) footnotes option.
- [ ] Add heading ids as a default on extension.
- [ ] Add opt-in deflist support.
- [ ] Decide if lambdas actually provide any value.
- [ ] configure date format as a partial

## General 
- [ ] Integrity hash
  - Allows users to verify their output didn't change after upgrading to a new version
- [ ] Content-hash fingerprinting for CSS and JS cache busting
- [ ] Avoid `json.Value` / `json.Object` where possible.
- [ ] make `parse` an overload of `parse_text/parse_inline` and `parse_file`, or something.
- [ ] Add page params
- [ ] We must remove all mention of `posts` from the odin code.
      At present, "posts" are a user-level construct defined as pages in a
      particular collection.
- [ ] running ./thor/thor still logs the debug message: using config /home/spencer/github.com/sbrow.github.io/thor.json
  - wrong cwd?
- [ ] Clean up the default layouts
- [ ] if no `html` tag detected in output, re-render output with base template
      (or whatever template is next in the chain)
- [ ] Add `-production` flag
  - sets `-minify`
- [x] Mustache diagnostics
  - [x] Rust-style error messages: position tracking on Node/Template/Data_Error, `diagnostic.odin` with `format_error`, ANSI colors via `core:terminal/ansi` (Phase 1+2+3)
  - [x] Unknown-key detection with Levenshtein suggestions (`core:strings/levenshtein_distance`); warning severity (Phase 4+5)
  - [x] Strict-by-default posture: warn on missing keys in `{{k}}`/`{{{k}}}`/`{{#k}}`/`{{^k}}`, missing partials, missing parents, unmatched block overrides
  - [x] Block-override source-template tracking: warnings inside overrides point at the override's source file, not the parent template
  - [ ] Partial invocation stack in diagnostics: when an error fires inside a partial, show "invoked from" chain through `{{> name}}` calls. Currently warnings inside partials point at the partial (correct file) but don't show the invocation site.
  - [ ] Could be better error message when missing a closing (or opening) brace
- [ ] Block attributes on code fences (`{ #ex-1 }`) — hello-world.md
- [ ] include-code shortcode (`{{< include-code ... >}}`) — i-ported-fd-to-odin
- [ ] follow symlinks in `scan_content`?
- [ ] ensure sidenote numbers render in display order and not in declaration order.
- [x] We need to be able to do `Year_Section` in a non-magical, unprivileged way. Implemented via the pipes extension to mustache — see [mustache/EXTENSIONS.md](mustache/EXTENSIONS.md).
- [ ] Table of contents support.
- [ ] Nav items should be active when the current page is selected.
- [ ] Theme selector for syntax highlighting.
  - use http://github.com/helix-editor/helix/tree/master/runtime/themes) as a
    guide
- [ ] grammars
  - [ ] Search in multiple places
  - [ ] Download missing grammars.
  - [ ] Durable highlight paths: read `GRAPHS_PATH`/`QUERIES_PATH` from env vars set by the flake instead of hardcoded nix store hashes, so they survive `nix flake update` and let the grammar/query version-mismatch detector fire automatically.
- [ ] CI
  - [ ] Syntax highlighting in production: CI (`nix build` on ubuntu-latest) has no grammar `.so`s and a machine-specific `QUERIES_PATH` nix store hash, so the deployed site renders unhighlighted. Provide grammars + queries as nix build inputs and pass paths to thor at runtime (env vars/flags).
- [ ] Unit tests for highlighting helpers: `capture_name_to_css`, `escape_html`, `unescape_html`, `extract_query_token`, `helix_version_from_path`.
- [ ] `<pre><code>` blocks need to set background to theme background,
  regardless of prefers-dark. (or use a different theme)
- [ ] `-watch` flag
  - [x] basic poll loop
  - [ ] filesystem poll loop
  - [ ] event based
- [ ] Free cmark HTML output (`body_html`) — cmark allocates via C malloc, not the arena, so it leaks per iteration in watch mode
- [ ] Mount content in VFS
- [ ] commands
  - [ ] `build` alias of default
  - [ ] `new site` set up new project
- [ ] warn/error when unknown key used in mustache.
- [ ] Import/export packages. Hugo, jekyll, WordPress, etc.

## Notes

from the [Hugo docs](https://gohugo.io/quick-reference/glossary/#default-sort-order)

default sort order
: The default sort order for page collections, used when no other criteria are set, follows this priority:
  1. weight (ascending)
  2. date (descending)
  3. linkTitle falling back to title (ascending)
  4. logical path (ascending)

## Code Review

A human should manually review every file in the project. AI cannot complete
these tasks.

- [ ] Review every file in thor
  - [ ] Review assets.odin
  - [ ] Review content.odin
  - [ ] Review defaults.odin
  - [ ] Review feed.odin
  - [ ] Review frontmatter.odin
  - [ ] Review main.odin
  - [ ] Review minify.odin
  - [ ] Review `markdown/`
    - [x] Review alerts.odin
    - [x] Review alerts_test.odin
    - [x] Review emoji.odin
    - [x] Review emoji_test.odin
    - [ ] Review footnotes.odin
    - [ ] Review footnotes_test.odin
    - [ ] Review highlight.odin
    - [ ] Review markdown.odin
    - [x] Review sectionate.odin
    - [x] Review sectionate_test.odin
    - [ ] Review suggest.odin
    - [ ] Review suggest_test.odin
  - [x] Review opengraph.odin
  - [ ] Review render.odin
  - [x] Review site.odin
  - [ ] Review treesitter/treesitter.odin
  - [ ] Review vfs.odin
- [ ] Review procs
  - [ ] markdown.transform_alert
