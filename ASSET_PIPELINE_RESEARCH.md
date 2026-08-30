# Asset Pipeline Research: Bring-Your-Own CSS Preprocessor

Research and design notes for letting thor users bring their own CSS toolchain
(Sass, PostCSS/Tailwind, Less, Lightning CSS, …) instead of thor embedding or
tracking any of them.

## Problem statement

The CSS pre-processor landscape is large and moving (Tailwind, PostCSS, Less,
Sass, Lightning CSS, …). thor is a ~1.9 MB self-contained binary that tracks its
own size (see `AUDITING_BINARY_SIZE.md`); bundling any one preprocessor — let
alone keeping up with all of them — is a non-starter on both size and
maintenance grounds. So "bring your own" has to mean **thor orchestrates the
tool the user already installed**, never reimplements it.

Today `copy_assets_dir` (`assets.odin`) copies everything under `assets/` to the
output dir and optionally minifies `.css` via the tree-sitter pass in
`minify.odin`. There is no preprocessing seam.

## What we are NOT doing, and why

- **Bundle a specific preprocessor** — rejected: binary-size-hostile, and picks
  winners in a space we said we can't keep up with.
- **Hugo Pipes-style template resource pipeline** (`resources.Get | css.Sass |
  minify | fingerprint`) — powerful, but needs a resource abstraction and a
  non-logic-less template language to host the chained syntax. thor's engine is
  logic-less mustache; wrong fit.
- **Curated shell-out for named tools only** (what Hugo actually ships — only
  `css.Sass` and `css.PostCSS` shell out) — this just re-picks winners.

The chosen direction reuses thor's **existing mustache pipe grammar** (the same
mechanism as the `rel_url` pipe) to express asset transforms declaratively,
where the asset is referenced.

## Correcting the record on Hugo

An earlier draft attributed a generic "pre/post-build shell hook" model to Hugo.
That is wrong. Hugo has **no** generic build hooks. Its CSS handling is Hugo
Pipes — a *template-invoked resource pipeline* of fixed, named functions
(`css.Sass`, `css.PostCSS`, `minify`, `fingerprint`, `resources.Concat`, …).
Only two of those shell out: `css.PostCSS` (to a local `postcss-cli` under Node)
and `css.Sass` (embedded LibSass, or a `dart-sass` binary). Generic
"run any command pre/post build" is closer to npm-scripts / Makefile glue, or
Eleventy's `before`/`after` events (which run JavaScript, not shell commands).
No mainstream SSG markets a generic command hook as its asset story.

---

## Tool CLI research

Five representative tools were researched for their exact shell-out contract.
The questions that determine thor's interface are the same for each: stdin/stdout
vs. file-path args, whether a config file is mandatory, whether it needs to scan
rendered HTML, watch support, minify overlap, and runtime dependencies.

### Mechanical matrix

| Tool | stdin→stdout | Config file | Self-contained (no Node) | Self-minifies | Errors |
|---|---|---|---|---|---|
| **Dart Sass** | yes (`sass -`) | none | yes — standalone binary | `--style=compressed` | stderr, exit 65 |
| **PostCSS** (`postcss-cli`) | yes (`< in > out`) | optional (`--use`) | **no** — needs Node + node_modules | via cssnano plugin | stderr, exit 1 |
| **lessc** | yes (`-` / positional) | none | **no** — needs Node | weak/deprecated (`-x`) | stderr, nonzero |
| **Lightning CSS** | file-in, stdout-out | none (flags) | yes — Rust binary (npm-distributed) | `--minify` (its core purpose) | stderr, nonzero |
| **Tailwind v4** | yes (`-i - -o -`) | none (CSS-first) | yes — standalone binary (Bun) | `--minify` | stderr, nonzero |
| **Tailwind v3** | no (needs `-i` file) | `tailwind.config.js` | yes — standalone (pkg/Node embed) | `--minify` | stderr, nonzero |

Two properties are uniform and load-bearing:

- **Every tool writes errors to stderr and returns nonzero on failure.** thor can
  gate on exit code and surface stderr through a single code path for all tools.
- **Every tool can stream to stdout.** Differences (Lightning CSS wants a path
  not stdin; lessc's output is positional; Tailwind v3 needs an input file) are
  all absorbable by a per-tool command template with placeholders.

### Per-tool detail

**Dart Sass** — `sass input.scss output.css`, or `sass -` for stdin, prints to
stdout when no output arg. No config file exists or is supported; configured by
CLI flags + `@use`/`@import` in source. Load paths via `--load-path`/`-I`.
`--style=compressed` minifies (overlaps thor's minifier). Source maps on by
default (`--no-source-map` to disable). Exit 64 = usage error, 65 = compile
error. **Distribution:** standalone release bundles the Dart VM + snapshot, no
Node; the npm `sass` package is dart2js and needs Node. Prefer the standalone.

**PostCSS** (`postcss-cli`, binary `postcss`) — positional input files or stdin;
stdout is the default when no `-o`/`--dir`/`--replace`. Config (`postcss.config.js`
/ `.postcssrc`, cosmiconfig, walks up) is **not required** — plugins can be given
with `-u/--use` (e.g. `postcss in.css -u autoprefixer -u cssnano -o out.css`).
Zero plugins = near pass-through. **postcss is only a plugin host** — autoprefixer,
tailwind, cssnano are separate npm packages resolved from `node_modules`.
`-w/--watch` tracks the full `@import` dependency graph via PostCSS `dependency`
messages. Exit 1 on error, errors to stderr, stdout stays clean for piping.
**Hard Node + node_modules dependency.** Invoke via `npx postcss` to resolve
local `.bin`.

**lessc** — `lessc [opts] <source> [destination]`; `-` reads stdin; stdout when
destination omitted (**no `-o` flag** — output is positional). No config file;
`.less` source + flags. `--include-path` for import search. `-x`/`--compress` is
deprecated/weak — let thor's minifier compress. **No CLI watch mode** (watch only
exists in the browser runtime). Errors to stderr, nonzero on compile error.
**Hard Node dependency** (`bin/lessc` is a Node script).

**Lightning CSS** (`lightningcss`) — input file positional, `-o`/`--output` or
stdout when omitted. No config, flag-driven. `--minify` is the tool's core
purpose (**directly overlaps thor's minifier** — pick one). `--bundle` inlines
`@import`s; `--targets "<browserslist>"` downlevels modern CSS. No built-in watch.
Errors to stderr, nonzero. **Runtime: self-contained Rust binary, no Node to
run** — but distribution is npm-only (`lightningcss-cli` pulls a platform package
like `lightningcss-cli-linux-x64-gnu`); no official GitHub/Homebrew/Winget
binaries. Can extract the binary from the npm registry tarball and run it
standalone.

**Tailwind CSS standalone CLI** (v3 and v4) — both ship a self-contained
per-platform binary (`./tailwindcss`), no Node required (v3 via Vercel pkg, v4
via Bun). `-i`/`--input`, `-o`/`--output` (defaults to stdout in v4). v4 reads
stdin with `-i -`; v3 effectively needs an input file. Input is a CSS entry file:
v3 uses `@tailwind base/components/utilities;`, v4 uses `@import "tailwindcss";`.
**Config:** v3 uses `tailwind.config.js` (auto-discovered, `-c` to override) and
in practice needs it (or `--content`) to know what to scan; v4 is CSS-first and
genuinely zero-config. `--minify` in both. Errors to stderr, nonzero (codes not
formally enumerated — check `exit != 0`).

**Content scanning (the critical Tailwind property):** Tailwind scans
source/template files **as plain text** for complete, static class-name tokens.
It does not parse code and does not strictly require rendered HTML — it scans
whatever files you point it at. But for an SSG the safe strategy is to scan the
**generated output** after render, so classes that only appear post-render aren't
missed. v3: `content: ["./public/**/*.html"]` or `--content`. v4: automatic
detection, but it **ignores `.gitignore`d paths** — so a git-ignored `public/`
must be added explicitly with `@source "../public"`.

---

## Design conclusions

### The one split that matters: two tool shapes

The research draws a hard line between two categories that need **different
integration surfaces**:

1. **Per-asset transformers** — Sass, Less, Lightning CSS, PostCSS-as-compiler.
   Input = one source file → output = one CSS file. These fit a mustache pipe:
   `{{ "css/main.scss" | tool sass }}`. Each tool's CLI quirk (stdin vs. path,
   positional output, etc.) is absorbed by a per-tool command template.

2. **Whole-output scanners** — Tailwind, alone. Its "input" is not one asset; it
   is an entry CSS file **plus every rendered HTML file it scans**. At the moment
   a per-page pipe would fire, the full output does not exist yet. Tailwind must
   run **once, after all HTML is written, pointed at `output_dir`**. That is a
   post-render step, categorically not a pipe.

### The chicken-and-egg, and the fix

A `<link>` wants a **fingerprinted (cache-busted) URL**, but for Tailwind the CSS
isn't produced until **after** render — so at render time the template cannot
know the hash. Hugo dodges this with a lazy multi-pass resource graph; thor is
single-pass.

**Resolution — emit a placeholder at render, resolve at the end.** A pipe like
`{{ "css/main.scss" | tool sass | fingerprint }}` writes a **stable token** (e.g.
`⟦asset:css/main.scss⟧`) into the HTML. After render, thor runs the tools,
populates a **content-addressed asset registry** (logical name → final hashed
URL), then does one cheap string-replace pass over the output swapping tokens →
real URLs.

This single mechanism dissolves every constraint encountered:

- **Cache-busting:** the hash is known at resolve time, so the token becomes
  `/css/main.a1b2c3.css` uniformly, even for tools that rename output themselves.
- **Hash-after-minify:** resolution is the last step, so the hash is always of the
  exact final served bytes.
- **Same asset → same hash across N pages:** the registry is computed once; every
  token resolves identically. (This is also the memoization that keeps a
  per-page pipe from shelling out N times for the same file.)
- **Tailwind:** its post-render output lands in the registry like any other asset;
  tokens that referenced it resolve correctly despite the CSS not existing at
  render time.

### Cache-busting: two regimes

- **Regime A — thor owns the hash (recommended, and what every researched
  compiler needs).** Tool → stdout → thor minifies → thor hashes the final bytes →
  writes `main.<hash>.css` → registers the URL. None of Sass/PostCSS/Less/
  Lightning CSS/Tailwind fingerprint on their own; fingerprinting is a
  bundler/plugin behavior. thor stays in full control of the name because it
  writes the file. Mirrors Hugo's `| fingerprint` → `.RelPermalink`.
- **Regime B — the tool owns the hash** (bundlers: esbuild/vite/parcel, or
  PostCSS + `postcss-hash`). The tool renames output to a name thor can't predict,
  and stdout capture doesn't reveal it. The standard answer these tools already
  provide is a **manifest** (`manifest.json` mapping `"main.css"` →
  `"main.a1b2c3.css"`). Supporting this class means thor ingests that manifest
  into the same registry rather than scanning for files.

Both regimes converge on the same abstraction: **a build-scoped, content-addressed
asset registry** (logical name → final emitted URL), populated by thor's own
transform+fingerprint or by an external tool's manifest, and resolved through the
placeholder pass.

## Proposed interface shape

- **`thor.json` `tools` table** — one command template per tool. Keeps shell
  commands out of templates (a single trust surface), and absorbs each CLI's
  quirks. `$in` = source path; stdout is captured:

  ```json
  "tools": {
    "sass":         "sass --no-source-map $in",
    "postcss":      "postcss -u autoprefixer $in",
    "lightningcss": "lightningcss --minify $in",
    "tailwind":     { "run": "tailwindcss -i $in -o -", "scan": "output" }
  }
  ```

  The `scan: output` marker flips a tool from per-asset (pipe) to post-render
  (whole-output) mode.

- **Pipe ops** — `tool <name>` (transform → asset handle), `minify`,
  `fingerprint` — all resolving through the registry, chainable with the existing
  `rel_url`:

  ```
  <link href="{{ "css/main.scss" | tool sass | minify | fingerprint | rel_url }}">
  ```

  A lookup-direction op resolves a logical name to its final URL:
  `{{ "css/main.css" | asset }}` → `/css/main.a1b2c3.css`.

- **Final resolve pass** over `output_dir` replacing asset tokens with registry
  URLs. This is also where post-render scanners (Tailwind) have already run.

### Fit with the existing mustache pipe grammar

`{{ "css/main.css" | tool postcss }}` already parses under `mustache/pipes.odin`:
the key is a quoted literal (`tokenize_fields` keeps the quotes so a literal is
distinguishable from a context key), `tool` is the op, `postcss` is one arg
(under `MAX_PIPE_ARGS = 2`). Adding an op is the documented one-liner path — a
variant on `Pipe_Op` plus a `case` in `apply_filter`. The only architectural
departure from existing ops (all pure value→value string transforms) is that
`tool`/`fingerprint` have side effects (subprocess, file write) and must be
backed by the registry — which is why the placeholder + deferred-resolve model
matters: it keeps render itself side-effect-light and pushes the real work to a
defined post-render phase.

## Cross-cutting decisions

1. **Node dependency is not thor's problem.** PostCSS and lessc require Node +
   node_modules; Sass/Lightning CSS/Tailwind ship self-contained binaries. thor's
   job is to exec whatever is on PATH and **fail gracefully with the tool's
   stderr** if it's absent — never bundle, never assume a runtime. The Nix flake
   makes pinning the toolchain pleasant for users who want reproducibility.
2. **Minification must be explicit, never doubled.** Every one of these tools can
   self-minify, and thor has its own minifier. Make `minify` an explicit pipe
   step and do **not** auto-apply thor's global minify to tool-produced assets —
   otherwise `| tool lightningcss` (already minified) gets re-minified. The pipe
   chain is the single source of truth for whether/when an asset is minified.
3. **thor drives the watch; ignore the tools' own `--watch`.** thor already polls
   (5 s). Invoke each tool once per build as a pipeline step. Sass/PostCSS/
   Tailwind have watch modes, but running them would put a second watcher in
   competition with thor's loop — avoid it.

## Headline

The feature is not "a `tool` pipe." It is a **content-addressed asset registry
with deferred token resolution**, exposed through two pipe ops (`tool`,
`fingerprint`/`asset`) plus one post-render hook (for whole-output scanners like
Tailwind). That is the minimum that handles both tool shapes *and* cache-busting
without introducing a multi-pass render engine.

## Open questions for the design phase

- Placeholder token format and collision-safety (must survive HTML minification
  untouched — likely treat like the `pre`/`code` preserve ranges in `minify.odin`).
- Registry lifetime and keying (content hash vs. path+mtime) and how it threads
  through the watch loop for incremental rebuilds.
- Whether `fingerprint` is terminal-only, or the resolve pass always hashes
  post-minify regardless of chain position.
- Manifest ingestion format for Regime B (adopt Vite/webpack `manifest.json`
  shape?).
- Error policy: hard-fail the build vs. warn-and-skip when a tool exits nonzero
  or is missing from PATH (probably configurable, defaulting to fail).

## Sources

- Tailwind CLI (v4): https://tailwindcss.com/docs/installation/tailwind-cli ·
  content detection: https://tailwindcss.com/docs/detecting-classes-in-source-files ·
  standalone: https://tailwindcss.com/blog/standalone-cli ·
  v3: https://v3.tailwindcss.com/docs/installation ·
  https://v3.tailwindcss.com/docs/content-configuration
- PostCSS CLI: https://github.com/postcss/postcss-cli (README + `index.js` +
  `lib/args.js`)
- Dart Sass CLI: https://sass-lang.com/documentation/cli/dart-sass/ ·
  https://github.com/sass/dart-sass
- Less: https://lesscss.org/usage/ ·
  https://github.com/less/less-docs/blob/master/content/usage/command-line-usage.md
- Lightning CSS: https://lightningcss.dev/docs.html ·
  https://github.com/parcel-bundler/lightningcss ·
  https://www.npmjs.com/package/lightningcss-cli ·
  distribution discussion: https://github.com/parcel-bundler/lightningcss/discussions/732
