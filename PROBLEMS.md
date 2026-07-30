# Thor — UX Problems Catalog

Adversarial review of error messages, behavioral inconsistencies, and user
frustration points. Established as a baseline on commit `314cab2`.

Each entry cites the source location so it can be tracked to a fix.

---

## Severity legend

- **Critical** — user mistake produces silent wrong output or an unhelpful
  fatal error with no path forward.
- **High** — error or warning is emitted but missing "where" or "how to fix."
- **Medium** — inconsistency or gotcha that causes confusion or rework.
- **Low** — polish / minor frustration.

---

## A. Silent wrong output (no error, wrong result)

These are the most dangerous — the user gets *no signal* that something is wrong.

### A1. Non-JSON frontmatter silently treated as body content — Critical
`frontmatter.odin:26`

Thor expects JSON frontmatter delimited by bare `{` / `}` lines. A user
coming from Hugo/Jekyll writes YAML (`---`) or TOML (`+++`) frontmatter. It is
silently swallowed into the markdown body. No title, no date, no draft flag —
and no error. Likely the #1 onboarding trap.

### A2. Unknown `thor.json` keys silently ignored — Critical
`site.odin:162`

`json.unmarshal_string` skips unknown fields. A typo like `"tittle"` instead
of `"title"` produces a silently-empty title. No warning. (`TODOS.md` already
wants a JSON schema.)

### A3. Draft pages silently excluded — High
`content.odin:64`

When `-drafts` isn't passed, draft pages vanish with no log. User adds a
page, forgets the flag, page doesn't appear — zero feedback.

### A4. Naive singularization for layout inference — High
`content.odin:202`

`posts` → `post` (correct), but `series` → `serie`, `news` → `new`. The
layout silently falls through the fallback chain to `page`/`base`. No
"layout 'serie' not found for section 'series'" message — only a debug log
that's off by default.

### A5. `base_url` defaults to `localhost:8080` — Critical
`site.odin:100`

Forgetting to set it means every canonical URL, OG tag, and RSS link points
to localhost. No warning. Devastating in production builds.

### A6. Missing `content/` produces empty build — High
`content.odin:82`

`scan_content_files` logs a `warnf`, the build proceeds with zero pages, then
`log.infof("Rendered 0 pages")`. No fatal error, no "did you create
content/?" guidance.

### A7. RSS emits sentinel epoch date silently — Medium
`feed.odin:33`

Pages without a date get `"Mon, 01 Jan 0001 00:00:00 +0000"` in `<pubDate>`.
No warning that a page is dateless in the feed.

### A8. `format_rfc822` returns raw ISO on parse failure — Medium
`feed.odin:122-125`

`// TODO: should indicate error somehow` — short/malformed dates get embedded
verbatim in `<pubDate>`, producing invalid RSS with no warning.

---

## B. Error messages missing "where" or "how to fix"

### B1. `render_template` blanks the entire page on error — Critical
`render.odin:119-133`

A single bad tag/pipe anywhere produces `log.errorf` + `return ""`. The
output file is silently written empty. In a `nix build` (no visible
terminal), the user sees a blank page with zero clue why. Already noted in
`TODOS.md`.

### B2. Malformed `thor.json` degrades to defaults — Critical
`site.odin:162-168`

A JSON syntax error is a `warnf`, then `site_apply_path_defaults` kicks in.
The site builds with wrong paths and produces a confusing empty result — the
cause is two hops removed from the symptom.

### B3. Frontmatter parse error has no file location — Critical
`frontmatter.odin:41`

`"failed to parse frontmatter JSON: %v"` — no filename. On a 100-post site
the user can't find the bad file. Worse: `ok=false` silently drops the page
entirely.

### B4. `get_template` returns empty `Template{}` on missing base — High
`render.odin:88-89`

`"base.html not found in VFS"` — no guidance on how to fix (create the file,
check modules, etc.).

### B5. `dlopen` failures lack the OS reason and fix guidance — High
`treesitter/treesitter.odin:200-219`

"cannot load grammar %s (%s)" shows the path but not *why* (no `dlerror()`).
No guidance: "set the 'grammars' key in thor.json" or "this .so may be for a
different tree-sitter ABI."

### B6. Menu-mix fatal lacks location — High
`menus.odin:42`

`"cannot mix config menus with frontmatter menus"` — doesn't name which pages
have frontmatter menus.

### B7. Minify error doesn't name the page — Medium
`minify.odin:33`

"minify: HTML parse errors, skipping minification" — across 50 pages, which
one?

### B8. Timezone load failure is a warning with no guidance — Medium
`site.odin:148`

Doesn't state impact (dates render in UTC) or suggest valid names. Already
in `TODOS.md`.

### B9. No "config not found" message — Medium
`site.odin:113`

Silently falls back to `./thor.json`. Wrong-directory runs produce a
confusing default build.

---

## C. Silent skip of invalid user input

### C1. Unknown markdown extensions silently ignored (CLI) — High
`markdown/markdown.odin:49-68`

`parse_extension_list` has a switch with no default case. `-ext:higlight`
(typo for `highlight`) is silently a no-op.

### C2. Unknown markdown extensions silently ignored (config) — High
`markdown/markdown.odin:71-90`

`apply_extension_config` has a `// TODO: Silently discards invalid values.`
Unknown keys in `thor.json`'s `markdown_extensions` are silently dropped.
Non-boolean values are `or_continue`d.

---

## D. Naming inconsistencies

### D1. Markdown extensions have 3+ names — Medium

| Context | Name |
|---|---|
| `thor.json` key | `markdown_extensions` |
| CLI flag | `-ext` / `-no-ext` |
| Struct fields | `md_enable` / `md_disable` |
| JSON/CLI values | `emoji`, `sidenotes` (lowercase) |
| Enum members | `.Emoji`, `.Sidenotes` (PascalCase) |

### D2. `-ext` usage string omits `heading_ids` — Medium
`site.odin:91`

The help text lists `emoji,sidenotes,alerts,highlight,sections` but the enum
also has `HeadingIDs`. Users can't discover it from `--help`.

### D3. Starred field has three names — Low
- `Page.starred` (`content.odin:28`)
- `Frontmatter.isStarred` (`frontmatter.odin:17`) — so the JSON key is `isStarred`
- `AGENTS.md:101` says `is_starred` (stale)

### D4. Inconsistent error severity for similar failures — Medium
- Template **parse** error → `log.errorf` + `os.exit(1)` (fatal) — `render.odin:37-49`
- Template **render** error → `log.errorf` + return `""` (non-fatal, blank page) — `render.odin:126-131`
- Config parse error → `warnf` + fallback to defaults — `site.odin:163-165`

Same category of failure (user wrote something wrong) with wildly different
consequences.

### D5. Dead `os.exit(1)` after `log.fatalf` — Low
`render.odin:33`, `menus.odin:43`

`fatalf` already exits; the following line is dead code.

---

## E. Configuration gotchas

### E1. `"menus": {}` is a stealth opt-out — Medium
`menus.odin:31-38`

An empty object silently disables *all* auto-menus. A user who adds the key
intending to configure later quietly loses their nav. The semantics (absent
≠ empty) are undocumented outside code comments.

### E2. Config precedence is invisible — Medium
`site.odin`

CLI > JSON > defaults, but there's no "resolved config" log. Debugging "why
is my base_url wrong?" requires reading source.

### E3. `format` pipe logs ERROR but still renders — Medium
`pipes.odin:261-265`

Missing `date.format` produces `log.errorf` but falls back to
`DEFAULT_DATE_FORMAT`. The severity says "error" but the behavior says
"warning."

---

## F. File/directory behavior surprises

### F1. Root dirs = sections, nested dirs = leaf bundles — Medium
`content.odin:108-127`

This meaningful semantic distinction is entirely implicit.
`content/about/team.md` is a leaf bundle (page "about" with body from
team.md), not a section "about" with page "team". No error or guidance when
the user's mental model differs.

### F2. Missing `layouts/` silently uses defaults — High
`vfs.odin:38-40`

`mount_dir` returns silently if the directory doesn't exist. Wrong path →
all user templates missing → defaults used. No "layouts directory X not
found" message.

### F3. Missing section index silently synthesized — Medium
`render.odin:316-326`

A section with pages but no `index.md` gets a synthetic `Page` with only a
title. No warning. User expecting an error gets a mostly-blank page.

### F4. Windows line endings silently break frontmatter — Medium
`frontmatter.odin:26`

`has_prefix(content, "{\n")` fails on `\r\n`; the JSON is treated as body.
Zero feedback.

---

## G. Template authoring frustrations

### G1. Template fallback chain is silent at Info level — Medium
`render.odin:84`

Only `log.debugf`, which is off by default (`main.odin:48` sets `.Info`).
User's custom layout silently ignored, defaults used.

### G2. Render error blanks entire page — Critical
`render.odin:126-131`

(Same as B1 — restated here for the template-authoring perspective.) One bad
tag → whole page `""`. The most impactful silent failure in the system.

### G3. Pipe errors lack "did you mean?" suggestions — High
`mustache/pipes.odin:241`

Unknown key errors (`{{tittle}}`), missing partials, and unmatched block
overrides all get Levenshtein "did you mean?" hints via `suggest_correction`.
But unknown pipe operations (`{{date | formats}}`) get only `"unknown pipe op
'formats'"` with no suggestion. The known filter names (`"format"`,
`"group_by"`) are a small fixed set — perfect for suggestions.

Structural gap: `Error_Body` has no `hint` field, and
`format_render_error` doesn't pass `hint` to `format_error` (defaults to
`""`). So even if a suggestion were computed, there's nowhere to put it
without either appending to `msg` or adding `hint` to `Error_Body`.

### G4. Triple-mustache `{{{` mishandled by `tag_content_base` — Medium
`mustache/mustache.odin:230`

`tag_content_base` skips `{{` and sigils (`#^/&><$!`) to find where tag
content begins. But triple-mustache `{{{key}}}` is common — after `{{`,
the next char is `{`, which is not in the sigil list, so `base` points at
`{` instead of the actual key content. Any pipe position calculation for
`{{{key | format}}}` will be off by one byte.

---

## Cross-cutting themes

1. **Debug-level logging masks important fallbacks.** Layout fallbacks,
   template misses, and grammar skips are all `debugf` — invisible at the
   default Info level. Users never learn their customizations were ignored.

2. **The system fails open, not closed.** Missing files, missing
   directories, missing config — all silently fall back to defaults rather
   than surfacing the problem. Friendly until it isn't.

3. **No "resolved state" visibility.** There's no way for a user to see what
   thor actually loaded: which layouts, which config values, which pages
   were skipped as drafts. The build is a black box.

---

## Gold-standard examples to emulate

These are the parts of the codebase that already do it right:

- **Mustache diagnostics** (`mustache/diagnostic.odin` + `suggest.odin`):
  rust-style multi-line context, caret underlines, Levenshtein "did you
  mean?" hints, file:line:col.
- **Treesitter query version-mismatch** (`treesitter/treesitter.odin:299-315`):
  explains the likely cause, shows both grammar/query versions, flags
  mismatches explicitly.
