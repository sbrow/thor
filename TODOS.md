## High priority

- Polish existing features before moving on to new ones.
- [ ] Do mustache's whitespace rules actually suit us, or should we make our own? 
- [x] `{{>title}}` default partial? `{{site.title}} | {{ page.title }}`
- [ ] implicit titles (Set when missing?)
- [ ] create a default `head.html`.
- [ ] html comments are rendered, except in minify mode.
- [ ] does it make sense for partials to be inside layouts?
  - current: `layouts/partials`
  - alt1: `layouts`, `partials`
  - alt2: `templates/layouts`, `templates/partials`
- [ ] [aliases](https://gohugo.io/methods/page/aliases/#redirects)?
- [ ] Improve diagnostics
  - [x] keep track of every error and don't report them more than once.
  - [ ] `*` make sure the frontmatter parser has good diagnostics.
  - [ ] fix the diagnostics in [DIAGNOSTIC TODOS](./DIAGNOSTIC_TODOS.yaml)
  - [ ] only report format errors once.
  - [ ] only report missing partiall errors once.
  - [ ] All Diagnostics should show:
    - [ ] *What* went wrong
    - [ ] *where* (in the file)
    - [ ] *where* (in the stack trace)
    - [ ] *how* you can fix it (if applicable)
  - [ ] Create a Location struct that somewhat matches Odin's [Source_Code_Location](https://pkg.odin-lang.org/base/runtime/#Source_Code_Location)?
    - Note that odin's version doesn't contain the stack trace.
  - [ ] show "stack traces" in template error diagnostics
  - [ ] better diagnostics for syntax errors in treesitter.
  - [ ] Ensure diagnostics for MAX_CONTEXT_DEPTH are good.
  - [ ] improve matching weights message.
  - [ ] Test menu diagnostics
  - [ ] Honestly, Test **all** diagnostics
  - [ ] Need to be careful about diagnostics across module boundaries.
    - we don't necessarily want to warn users about theme designers mistakes. (though perhaps we do)
  - [ ] consider reporting duplicate weights outside of menus
  - [ ] Extend `tag_error` to all render-time errors, not just pipe errors.
    Currently only pipe errors (4 sites in `render_nodes`) get stamped with
    the correct template source/path. Other render errors still use the
    content template's source/path, which can point at the wrong file.
  - [ ] try to make file paths clickable links.
  - [ ] centralize diagnostics to one place.
  - [ ] consider logging the number of times an error occurred.
- [ ] Load grammars dynamically
- [x] starred must be a param.
- [ ] Documentation
  - [ ] talk about the context stack (and its limit).
  - [ ] highlight the differences in the way menus are handled.
- [ ] consider sites with date based urls.
- [x] Don't show annoying log output in tests.
- [ ] improve home link customization.
  - [ ] currently an accessibility issue.
- [x] support JSON5 in in frontmatter
- [ ] Create a json schema file for `thor.json`.
- [x] cleanup `#partial switch`es.
- [ ] improve json diagnostics.
  - i.e. "Missing quotes around string", etc.
- [ ] don't use bullshit "sub-tokens", add filters and pipes as proper tokens.
- [ ] Ideas is now in the wrong spot. Date is wrong, and it is showing date
      when it shouldn't be.

## Performance

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

## Remove Privileged content

- [ ] `group_by` currently requires a computed `year` field on the page.
  - We should replace this with `{{ pages | group_by (date | "2006") }}` or similar


## Memory Management

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

## Markdown
- [ ] Add overloads for every extension - accept ^strings.Builder.
- [ ] Add conventional (Hugo style) footnotes option.
- [ ] Add opt-in deflist support.
- [x] Decide if lambdas actually provide any value.
- [ ] add tables extension
- [x] Table of contents support.
  - [ ] enable template level rendering of TOCs
  - [ ] Write css for toc sidebar and figure out where to put it.
  - [ ] Add [hugo style configuration](https://gohugo.io/configuration/markup/#table-of-contents)
- [ ] Link checker?
  - Checks all links on each page to make sure they are valid.
- [ ] Peruse [GitHub's](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
      docs for any juicy nuggets we may have missed.
- [ ] Avoid using `render_inline_md` if possible.

## Dates
- [ ] display an error when no part of the date appears in the output.
- [ ] Handle 0 and whitespace padding i.e. "_2" -> " 2"
- [ ] Do we *need* mustache.Date_Components, or can we use core:time/datetime.DateTime?

## General 
- [ ] Menus
  - [ ] configure opt-out of automatic sections being added to menu.
  - [ ] nested menus (i.e. `parent` support)
- [ ] get rid of the global variables in the `treesitter` package.
- [ ] enforce heading structure.
  - [ ] Either frontmatter.title set, or 1 h1 tag at top, not both
  - [ ] No skipping. 
- [ ] Consider using `or_else` when applying default values to structs. i.e.
```odin
package main

X :: struct {
  foo: string
}

main :: proc () {
  x: X  

  x.foo = x.foo or_else "bar"
}
```
- [ ] Integrity hash
  - Allows users to verify their output didn't change after upgrading to a new version
- [ ] Content-hash fingerprinting for CSS and JS cache busting
- [ ] come up with scrapers / scrape sources to harvest site data
  - we'll use this to help us sculpt defaults.
- [ ] merge `render_{section,home_html,page_html}` procs.
- [ ] try to combine render_page_html and render_home_html?
- [ ] Debug log stats. (analytics)
  - [ ] final Context_Stack cap
  - [ ] highest PIPE args used 
  - [ ] longest slug length + name that generated it
  - [ ] number of pages
  - [ ] number of blocks
  - [ ] enabled features / extensions
  - [ ] etc
- [ ] Avoid `json.Value` / `json.Object` where possible.
- [ ] make `parse` an overload of `parse_text/parse_inline` and `parse_file`, or something.
- [x] Add page params
- [ ] We must remove all mention of `posts` from the odin code.
      At present, "posts" are a user-level construct defined as pages in a
      particular collection.
- [ ] running ./thor/thor still logs the debug message: using config /home/spencer/github.com/sbrow.github.io/thor.json
  - wrong cwd?
- [ ] Clean up the default layouts
- [ ] Menus
  - [x] Detailed frontmatter menu form ("menu": {"main": {"weight": 5}})
  - [ ] Menu active state (pre-compute is_active based on page.permalink prefix match)
  - [x] Page.weight field for general-purpose page ordering (menus, lists, related posts)
- [ ] if no `html` tag detected in output, re-render output with base template
      (or whatever template is next in the chain)
- [ ] Add `-production` flag
  - sets `-minify`
- [ ] Mustache diagnostics
  - [ ] Partial invocation stack in diagnostics: when an error fires inside a partial, show "invoked from" chain through `{{> name}}` calls. Currently warnings inside partials point at the partial (correct file) but don't show the invocation site.
  - [x] Error message doesn't show position of faulty pipe name correctly.
  - [ ] `render_template` (`render.odin`) blanks the *entire page* to `""` on any
        mustache render error and only `log.errorf`s it — a single bad tag/pipe
        anywhere on the page silently kills the whole output with no visible
        signal outside the terminal log. Should at least be scoped to the
        failing tag/section, or surfaced somewhere the person building the
        site will actually see it.
  ```bash
  [ERROR] --- [138:render_template()] unknown pipe op 'formats'
 --> /home/spencer/github.com/sbrow.github.io/layouts/home.html:1:1
  |
1 | {{<base}}
  | ^^^^^^^^^
2 | {{$content}}
3 | <main>
```
- [ ] Block attributes on code fences (`{ #ex-1 }`) — hello-world.md
- [ ] include-code shortcode (`{{< include-code ... >}}`) — i-ported-fd-to-odin
- [ ] follow symlinks in `scan_content`?
- [ ] ensure sidenote numbers render in display order and not in declaration order.
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
- [x] Free cmark HTML output (`body_html`) — cmark allocates via C malloc, not the arena, so it leaks per iteration in watch mode
- [ ] manually pass `site_allocator` to `load_page`
- [ ] Mount content in VFS
- [ ] commands
  - [ ] `build` alias of default
  - [ ] `new site` set up new project
- [ ] warn/error when unknown key used in mustache.
- [ ] Import/export packages. Hugo, jekyll, WordPress, etc.
- [ ] opt-in "strict_keys" mode. in this mode, key lookups may not view parent objects.

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
