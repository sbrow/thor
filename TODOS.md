## Performance

- [ ] See if we can disable bounds checks in `write_indented` and elsewhere.
- [ ] Instead of loading the site fresh each time in watch mode, create a
      `reload_site` proc, that just updates changed resources.
- [ ] Only publish referenced assets.
- [ ] Split `load_page` into frontmatter-parse + body-process phases so draft pages can skip the markdown pipeline entirely
- [ ] Use spall to find ways to reduce run time.

## Memory Management

- [ ] Not sure whether to use temp allocator or site_allocator in opengraph.odin.
- [ ] Not sure whether to use temp allocator or site_allocator in `site_load_content`.
- [ ] Might not need to allocate in `strip_html_tags`

## Markdown
- [ ] Add overloads for every extension - accept ^strings.Builder.
- [ ] Add conventional (Hugo style) footnotes option.
- [ ] Add heading ids as a default on extension.

## General 
- [ ] Integrity hash
  - Allows users to verify their output didn't change after upgrading to a new version
- [ ] Content-hash fingerprinting for CSS and JS cache busting
- [ ] Avoid `json.Value` / `json.Object` where possible.
- [ ] running ./thor/thor still logs the debug message: using config /home/spencer/github.com/sbrow.github.io/thor.json
  - wrong cwd?
- [ ] Clean up the default layouts
- [ ] Add `-production` flag
  - sets `-minify`
- [ ] Open Graph
  - [x] mustache data keys for opengraph, etc.
  - [ ] OpenGraph meta tags — verify all fields match production site
  - [ ] set opengraph tags / description automatically if unset. (Like hugo does)
  - [ ] We can't use avatar.jpg as the default site image, that's unique to sbrow.github.io. We need to set that in the frontmatter of content/index.html. or possibly in the config
  - [ ] Add `og Open_Graph` to `Config_File` and if `Some`, use it as the base
        site og instead of `og_init()`?
    - If we go this route, `og_init` might not be the best name.
- [ ] Author should be a struct adhering to https://schema.org/author
- [ ] Block attributes on code fences (`{ #ex-1 }`) — hello-world.md
- [ ] include-code shortcode (`{{< include-code ... >}}`) — i-ported-fd-to-odin
- [ ] follow symlinks in `scan_content`?
- [ ] ensure sidenote numbers render in display order and not in declaration order.
- [ ] Add Opt-in deflist support.
- [ ] We need to be able to do `Year_Section` in a non-magical, unprivileged way. See [PLAN.md](PLAN.md) for computed properties approach.
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
  - [x] Review opengraph.odin
  - [ ] Review render.odin
  - [x] Review site.odin
  - [ ] Review treesitter/treesitter.odin
  - [ ] Review vfs.odin
- [ ] Review procs
  - [ ] markdown.transform_alert
