# TODOs

## Priority Unclear (Evaluate Later)

- [ ] Decide whether the grammar cache should support multi-threaded parsing.
  - For now it stays a single global cache used single-threaded; the plan is to
    guard the non-thread-safe parser/cursor use with a mutex when tests (or any
    future parallel caller) need it. A `TSParser`/`TSQueryCursor` is one-per-thread.
  - Alternative later: give each thread its own parser+cursor for real parallelism.
  - Also pin `init_persistent` to the heap allocator (lifetime bug, independent).
  - Full write-up: `GRAMMAR_CACHE_THREADING.md`.
- [ ] instead of `warnings: [dynamic]Error` we should use `warnings: [dynamic; 8]Error`
  - when limit reached, the template fails and stops rendering.
- [ ] Brainstorm plugin/tool/(postccs/less/tailwind/sass) support.

## General

Remember to polish existing features before moving on to new ones.

- [ ] Bake the default `layouts` into the binary at compile time via
      `#load_directory` so the binary is self-contained and doesn't read
      `DEFAULTS_PATH` from disk at runtime.
  - `#load_directory` is NOT recursive and its `name` is the base filename
    only, so `defaults/layouts` and `defaults/layouts/partials` must be loaded
    separately and mounted into the VFS with `data` set (not `fs_path`).
  - Removes the runtime dependency on `THOR_DEFAULTS_PATH` / `#directory` and
    the need to ship `defaults/` alongside the binary (see `flake.nix`).
- [ ] `build` command alias of default
- [ ] `new site` command to set up new project
- [ ] Some render errors blank the entire page instead of scoping to the failing tag.
- [ ] We must remove all mention of `posts` from the odin code.
      At present, "posts" are a user-level construct defined as pages in a
      particular collection.
- [ ] ? Clean up the default layouts (no idea what this means)
- [ ] `group_by` currently requires a computed `year` field on the page.
  - We should replace this with `{{ pages | group_by (date | "2006") }}` or similar
- [ ] does it make sense for partials to be inside layouts?
  - current: `layouts/partials`
  - alt1: `layouts`, `partials`
  - alt2: `templates/layouts`, `templates/partials`
- [ ] add `sort_by` pipe
- [ ] pipes
  - [x] first/last
    - [ ] write test for error when n == 0
    - [x] warn when using negative numbers
    - [x] warn when using default arg on string
    - [x] add the above warnings to DIAGNOSTIC_TESTS.md
    - [ ] Instead of "clearer form", be exact: "last 5"
    - [ ] write tests for `first 0` & `last 0`
    - [ ] update tests to assert diagnostics when appropriate
      - do we want to do this or just use DIAGNOSTIC_TESTS.md as the tests?
      - [ ] also update to use file logger so they don't clog up the output
    - [ ] narrow highlight in diagnostic to relevent part of line.
- [ ] page.url and page.permalink are confusing names. Switch to url + page_url
  - There is confusion over how to do this and whethor or not `| rel_url` should be needed to render these.
    Requires **careful thought**.

## Documentation

- [ ] talk about the context stack (and its limit).
- [ ] highlight the differences in the way menus are handled.
- [ ] explain that html/css/js comments are rendered, except in minify mode.

## Investigate

- [ ] running ./thor/thor still logs the debug message: using config /home/spencer/github.com/sbrow.github.io/thor.json
  - wrong cwd?

## Diagnostics

All diagnostics (errors) should show

- *What* went wrong
- *where* (in the file)
- *where* (in the stack trace)
- *how* you can fix it (if applicable)

- [ ] try to make file paths clickable links.
- [ ] make sure the frontmatter parser has good diagnostics.
- [ ] add all known diagnostics to [DIAGNOSTIC TODOS](./DIAGNOSTIC_TESTS.yaml).
- [ ] fix the broken diagnostics in [DIAGNOSTIC TODOS](./DIAGNOSTIC_TESTS.yaml)
- [ ] show *stack trace* for template partials?
- [ ] show where the typo occurred (config file path for `apply_extension_config`, full `-ext:value` for `parse_extension_list`)
- [ ] **all** diagnostics in [DIAGNOSTIC TODOS](./DIAGNOSTIC_TESTS.yaml) must be tested.
- [ ] only report format errors once.
- [ ] only report missing partial errors once.
- [ ] better diagnostics for syntax errors in treesitter.
- [ ] Ensure diagnostics for MAX_CONTEXT_DEPTH are good.
- [ ] improve matching weights message.
- [ ] Test menu diagnostics
- [ ] Extend `tag_error` to all render-time errors, not just pipe errors.
  Currently only pipe errors (4 sites in `render_nodes`) get stamped with
  the correct template source/path. Other render errors still use the
  content template's source/path, which can point at the wrong file.

## Analytics

Debug log stats:

- [ ] final Context_Stack cap
- [ ] highest PIPE args used 
- [ ] longest slug length + name that generated it
- [ ] number of pages
- [ ] number of blocks
- [ ] enabled features / extensions
- [ ] etc

## sbrow.github.io
- [ ] The home file was accidentally deleted in commit 9a9f731
- [ ] Ideas is now in the wrong spot. Date is wrong, and it is showing date
      when it shouldn't be.
