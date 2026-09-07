# Asset Pipeline Plan

Design for letting thor users bring their own CSS toolchain (Sass, PostCSS,
Lightning CSS, Tailwind, …).

## Thesis

Let thor users bring their own CSS toolchain by **orchestrating the tool they
already installed** — never bundling or reimplementing one. This is expressed
through thor's existing mustache pipe grammar with two new ops: `tool` and
`fingerprint`.

The earlier research design (content-addressed registry + deferred token
resolution + a separate post-render path for "whole-output scanners") is
**discarded**. It was overbuilt. Every tool — Tailwind included — scans
*source*, which exists at render time, so every transform runs **eagerly,
synchronously, and memoized**. No placeholder tokens, no post-render
string-replace pass, no second integration surface.

## The two ops

```html
<link href="{{ "css/main.scss" | tool sass | fingerprint | rel_url }}">
```

```json5
// thor.json
{
  "tools": {
    "sass":         "sass $in $out",
    "postcss":      "postcss $in -o $out",
    "lightningcss": "lightningcss --minify $in -o $out",
    "tailwind":     "tailwindcss -i $in -o $out"
  }
}
```

## Core model

The value flowing through the pipe is **bytes held by thor**, with a logical
name attached (`css/main.css`). Each stage transforms the bytes; the **final
stage publishes** one file to the output dir and returns its URL.

- A literal (`"css/main.scss"`) or context key names the **source** file on disk.
- `| tool <name>` runs a subprocess, replacing the carried bytes with its output.
- `| fingerprint` writes the content-addressed file and returns its hashed URL.
- The chain composes with the existing `rel_url` for base_url subpaths.

**Memoization:** results are cached per build, keyed by (op-chain, source). The
first page to reference an asset runs the tool; every other page hits the cache.
This is what stops N pages from shelling out N times.

## `| tool <name>`

Looks up `<name>` in the `thor.json` `tools` table and runs its command
template. `$in` and `$out` are **optional per-tool I/O adapters**:

| Template has | Behavior |
|---|---|
| `$in` | thor writes current bytes to a scratch path, substitutes it |
| no `$in` | thor pipes current bytes to the tool's **stdin** |
| `$out` | thor substitutes a scratch path, reads it back after |
| no `$out` | thor captures the tool's **stdout** |

Defaulting to stdin/stdout avoids scratch-file overhead when the tool supports
it. Tools that can't stream (Lightning CSS wants a path; Tailwind v3 needs an
input file) just get `$in`/`$out` in their template. Either way the bytes are
thor's, so chaining works regardless of each tool's preference:
`| tool sass | tool postcss` composes even if sass streams and postcss wants
files.

- **`$out` is always thor-controlled scratch** — the tool never picks the
  published filename.
- **Extension derivation:** thor owns the output name; `main.scss` through
  `tool sass` becomes `main.css`.
- **Errors:** thor gates on exit code and surfaces the tool's stderr through one
  code path. If the tool is missing from PATH, fail with its stderr — never
  bundle, never assume a runtime.
- **A bare `tool` (no `fingerprint`) still publishes** — to the logical unhashed
  path (`output/css/main.css`), returning `/css/main.css`.

## `| fingerprint`

Content-addresses whatever bytes it currently holds. It has **two outputs**:

- **Side effect:** writes `css/main.<hash>.css` to the output dir.
- **Return value:** the hashed URL string `/css/main.<hash>.css` (feeds
  `rel_url`).

Properties:

- **Works standalone**, no `tool` needed: `{{ "css/main.css" | fingerprint }}`
  is plain cache-busting of a hand-written file — probably the most common use.
- **Position decides what's hashed** — it hashes current bytes, so it belongs
  **last** in the chain. No terminal-only special-casing; the rule is just "put
  it last."
- **Hash format:** `name.<hash>.ext` (CDN-friendly), 8 hex chars of SHA-256.

## Tailwind is not special

It scans your **source** (`layouts/`, `content/`, partials) — which exists at
render time — so it runs synchronously like sass. Its `thor.json` entry just
needs content globs pointing at the source tree (or v4 auto-detection). The
**one** asymmetry is watch invalidation: sass re-runs when `main.scss` changes;
Tailwind must re-run when *any* scanned source changes. That's a cache-key
breadth difference, not an architectural one. The cost of scanning source vs.
output is losing dynamically-assembled class tokens (`col-{{n}}`) — a Tailwind
anti-pattern whose sanctioned fix is a safelist, not warping the build.

## Interaction: `copy_assets_dir`

Today thor copies everything under `assets/` to the output dir. Any source
consumed by a pipe must be **excluded from that plain copy** — otherwise you'd
ship the raw `main.scss` (or a dead unhashed `main.css` alongside the hashed
one). The pipe owns the write for assets it touches.

## Implementation steps (separable)

1. **`| fingerprint`** — no subprocess, no config. Hash + write + return URL,
   plus the `copy_assets_dir` exclusion. Smallest blast radius, independently
   useful, ships first.
2. **`| tool <name>`** — `thor.json` tools table, the `$in`/`$out`/stdin/stdout
   adapter, subprocess + exit-code/stderr handling, extension derivation,
   memoization. Composes with step 1.

## Open questions for implementation

- **Watch invalidation:** simplest correct v1 recomputes the memo each build
  (cheap for the common single-asset case). A cross-build skip keyed on source
  content/mtime is a later optimization — and Tailwind's broad content-glob key
  is where it matters most.
- **Source-map sidecars:** sass/lightning emit `.map` files next to `$out`;
  disable in the template or ignore the sidecar. Minor.
- **Error policy default:** hard-fail the build vs. warn-and-skip on tool
  failure/absence. Lean fail; possibly configurable later.
