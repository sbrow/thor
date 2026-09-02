# Definition-list test fixtures

Inputs (`../NN-name.md`) are the definition-list examples from
<https://www.markdownlang.com/extended/definition-lists.html>.

`pandoc/` and `hugo/` hold each input rendered by Pandoc (`-f markdown -t html5`)
and Hugo (Goldmark with `markup.goldmark.extensions.definitionList = true`).
They are retained as reference for a possible future "Option B" (full CommonMark
block semantics inside definitions). They are NOT the test oracle for the current
implementation.

`../expected/NN.html` is the oracle for `convert_deflists`: our inline fragment
format (no inter-tag newlines, no trailing newline), derived from the trusted
tool per the decisions below.

## Decisions (Option A — simple / inline)

Marker whitespace follows CommonMark: `:` with 0–3 spaces of indent is a
definition; 4+ (tab = 4) is a code block. Definition bodies are inline/flat.

Every fixture has a concrete exact-match oracle in `../expected/NN.html`.

| Fixture | Pandoc | Hugo | Decision | expected/ source |
|---------|--------|------|----------|------------------|
| 01-basic | `<dl>` | `<dl>` | support | hugo (agreed) |
| 02-multiple-defs | multi `<dd>` | multi `<dd>` | support | hugo (agreed) |
| 06-compact (`Term: Definition`) | `<p>` | `<p>` | NOT a deflist → passthrough | raw input |
| 07-extra-space (2-space `:`) | `<dl>` | `<p>` | support (accept, CommonMark ≤3-space rule) | hand-written |
| 08-glossary | `<dl>` | `<dl>` | support | hugo (agreed) |
| 09-api-params | multi `<dd>` | multi `<dd>` | support | hugo (agreed) |
| 05-nested | flattens | nested `<dl>` | flatten (matches Pandoc) | snapshot (== pandoc) |
| 03-multiline-def | ejects 2nd para | nests 2nd para in `<dd>` | degrade | snapshot (current output) |
| 04-markdown-in-def | flattens list | nested `<ul>`/`<blockquote>` | degrade | snapshot (current output) |

A detailed 3-way behavior comparison (ours vs Pandoc vs Hugo) for the diverging
fixtures is in `COMPARISON.md`, kept for Option-B review.

03/04/05 require block-level content inside `<dd>` (multi-paragraph, nested
lists/blockquotes, nested `<dl>`), which the inline preprocessor does not
produce. 05 flattens exactly as Pandoc does, so its snapshot equals Pandoc's
output. 03/04 emit a `<dl>` for the term and first line, then let the remaining
block content fall through as markdown; their `expected/` files snapshot that
current degraded behavior as a regression guard, not an endorsed rendering.
Revisit via Option B (full CommonMark block semantics) if real content needs it.
