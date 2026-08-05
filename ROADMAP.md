## v0.2.0

- [ ] [aliases](https://gohugo.io/methods/page/aliases/#redirects)?
- [ ] consider sites with date based urls.
- [ ] Create a json schema file for `thor.json`.
- [ ] Content-hash fingerprinting for CSS and JS cache busting
- [ ] Mount content in VFS
- [ ] `-watch` flag
  - [x] basic poll loop
  - [ ] filesystem poll loop
  - [ ] event based
- [ ] if no `html` tag detected in output, re-render output with base template
      (or whatever template is next in the chain). (Hugo seems to do this)
- [ ] Markdown
  - [ ] Block attributes extension — hello-world.md
  - [ ] add tables extension
  - [ ] enable template level rendering of TOCs
  - [ ] Write css for toc sidebar and figure out where to put it.
  - [ ] Add [hugo style configuration](https://gohugo.io/configuration/markup/#table-of-contents)
- [ ] implicit page titles (Set when missing?)
  -  guess from h1 tag or first h2 tag?  
- [ ] Syntax highlighting
  - [ ] grammars
      - [ ] load grammars dynamically
      - [ ] Search in multiple places
      - [ ] Download missing grammars.
      - [ ] Durable highlight paths: read `GRAPHS_PATH`/`QUERIES_PATH` from env vars set by the flake instead of hardcoded nix store hashes, so they survive `nix flake update` and let the grammar/query version-mismatch detector fire automatically.
  - [ ] Theme selector 
    - use http://github.com/helix-editor/helix/tree/master/runtime/themes) as a
      guide
  - [ ] Unit tests for highlighting helpers: `capture_name_to_css`, `escape_html`, `unescape_html`, `extract_query_token`, `helix_version_from_path`.
  - [ ] `<pre><code>` blocks need to set background to theme background,
    regardless of prefers-dark. (or use a different theme)
- [ ] Avoid `json.Value` / `json.Object` where possible.
- [ ] come up with scrapers / scrape sources to harvest site data
  - we'll use this to help us sculpt defaults.
- [ ] merge `render_{section,home_html,page_html}` procs.
- [ ] try to combine render_page_html and render_home_html?
- [ ] make `parse` an overload of `parse_text/parse_inline` and `parse_file`, or something.

### Menus

- [ ] Nav items should be active when the current page is selected.
- [ ] configure opt-out of automatic sections being added to menu.
- [ ] nested menus (i.e. `parent` support)

### Strict Mode 

- [ ] opt-in "strict_keys" mode. in this mode, key lookups may not view parent objects.
  - [ ] warn/error when unknown key used in mustache.
- [ ] enforce heading structure.
  - [ ] Either frontmatter.title set, or 1 h1 tag at top, not both
  - [ ] No skipping. 

### Dates
- [ ] display an error when no part of the date appears in the output.
- [ ] Handle 0 and whitespace padding i.e. "_2" -> " 2"
- [ ] Do we *need* mustache.Date_Components, or can we use core:time/datetime.DateTime?

## Beyond

- [ ] consider logging the number of times an error occurred. (diagnostics)
- [ ] Need to be careful about diagnostics across module boundaries.
  - we don't necessarily want to warn users about theme designers mistakes. (though perhaps we do)
- [ ] consider reporting duplicate weights outside of menus (diagnostic)
- [ ] Do mustache's whitespace rules actually suit us, or should we make our own? 
- [ ] create a default `head.html`?
- [ ] improve home link customization.
  - [ ] currently an accessibility issue.
- [ ] get rid of the global variables in the `treesitter` package.
- [ ] site-wide Integrity hash
  - Allows users to verify their output didn't change after upgrading to a new version
- [ ] Add `-production` flag
  - sets `-minify`
- [ ] manually pass `site_allocator` to `load_page`
- [ ] Import/export packages. Hugo, jekyll, WordPress, etc.
- [ ] shortcodes?
  - include-code shortcode (`{{< include-code ... >}}`) — i-ported-fd-to-odin
- [ ] follow symlinks in `scan_content`?
- [ ] Add overloads for every md extension? i.e. accept ^strings.Builder.
- [ ] content link checker?
  - Checks all links on each page to make sure they are valid.
- [ ] Peruse [GitHub's](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
      docs for any juicy nuggets we may have missed.
- [ ] Avoid using `render_inline_md` if possible.
- [ ] don't use bullshit "sub-tokens", add filters and pipes as proper tokens.
- [ ] Create a Location struct that somewhat matches Odin's [Source_Code_Location](https://pkg.odin-lang.org/base/runtime/#Source_Code_Location)?
  - Note that odin's version doesn't contain the stack trace.

### Memory Management

- [ ] Leaks in highlighter code.
- [ ] Not sure whether to use temp allocator or site_allocator in opengraph.odin.
- [ ] Not sure whether to use temp allocator or site_allocator in `site_load_content`.
- [ ] Might not need to allocate in `strip_html_tags`
- [ ] Fix `apply_filter`'s `format` case (`mustache/pipes.odin`) boxing `apply_format`'s
      `string` result into `any` via bare `return`, which materializes a hidden
      header temp in `apply_filter`'s own stack frame. Dangling once the frame
      returns; caused the `-o:speed` segfault in `write_value`. Fix: box explicitly
      with `any{new_clone(formatted, context.temp_allocator), typeid_of(string)}`.
- [ ] Same pattern in `apply_group_by` (`mustache/pipes.odin`): `return groups, nil`
      boxes a freshly-built `[dynamic]Group` as bare `any` — same latent
      stack-temp UB, hasn't crashed yet but should get the same treatment.

### Performance

- [ ] See if we can disable bounds checks in `write_indented` and elsewhere.
- [ ] Instead of loading the site fresh each time in watch mode, create a
      `reload_site` proc, that just updates changed resources.
- [ ] Only publish referenced assets.
- [ ] Split `load_page` into frontmatter-parse + body-process phases so draft pages can skip the markdown pipeline entirely
- [ ] Use spall to find ways to reduce run time.
- [ ] too many `write_string` calls in `highlight_block`
- [ ] return `src: cstring` from `load_query`.
- [ ] Improve `unescape_html` with simd.
- [ ] generate summary before syntax highlighting.
- [ ] generate summary before markdown to html conversion.
- [ ] mount_recursive is pretty significant
- [ ] thread pool for grammar loading is unbounded.
- [ ] load grammars async.
- [ ] during `load_page`:
  - pass each code block to the treesitter queue
  - continue working on the page,
  - `await` the highlighted code.
- [ ] can markdown extensions run in parallel?
- [ ] enforce MAX_SLUG_LENGTH
- [ ] enforce MAX_CONTEXT_DEPTH
- [ ] ensure struct fields are ordered correctly

