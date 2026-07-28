## High priority

- Polish existing features before moving on to new ones.
- [ ] Improve diagnostics
  - [ ] show "stack traces" in template error diagnostics
  - [ ] better diagnostics for syntax errors in treesitter.
  - [ ] Ensure diagnostics for MAX_CONTEXT_DEPTH are good.
  - [ ] show a proper diagnostic for timezones
    - currently "unable to load timezone 'America/New_Yorkskie'"
    - want rust style diagnostic and better message, maybe "unknown timezone 'America/New_Yorkskie'"
- [x] Simplify / unify template context stack. Come up with a name for it.
  - [x] `render_template` should accept `Template_Context`, not `any`
- [ ] Load grammars dynamically
- [x] consider adding a limit to the context stack in mustache.
- [x] Add heading ids as a default on extension.
- [ ] starred must be a param.
- [x] Add a `#config(MAX_CONTEXT_DEPTH, 16?)` to `mustache`.
- [ ] Documentation
  - [ ] talk about the context stack (and its limit).
- [ ] menu system
  - [ ] like Hugo's, but warn(/fail?) if menus are defined in the config *and* pages.
    - i.e. force the user to choose one or the other.
- [ ] Don't show annoying log output in tests.

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
- [ ] Decide if lambdas actually provide any value.

## Dates
- [ ] display an error when no part of the date appears in the output.
- [ ] Handle 0 and whitespace padding i.e. "_2" -> " 2"
- [ ] Do we *need* mustache.Date_Components, or can we use core:time/datetime.DateTime?

## General 
- [ ] get rid of the global variables in the `treesitter` package.
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
- [ ] Create a json schema file for `thor.json`.
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
- [ ] Mustache diagnostics
  - [ ] Partial invocation stack in diagnostics: when an error fires inside a partial, show "invoked from" chain through `{{> name}}` calls. Currently warnings inside partials point at the partial (correct file) but don't show the invocation site.
  - [ ] Could be better error message when missing a closing (or opening) brace
  - [ ] Error message doesn't show position of faulty pipe name correctly.
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
