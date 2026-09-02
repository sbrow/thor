# 3-way behavior comparison: ours vs Pandoc vs Hugo

Captured for later review (e.g. if we ever pursue "Option B" — full CommonMark
block semantics inside definitions). Compares `convert_deflists` output (Option A,
inline/flat) against Pandoc (`-f markdown -t html5`) and Hugo/Goldmark for the
four fixtures where behavior is interesting. Raw renderings live in `pandoc/` and
`hugo/`; ours is in `../expected/`. Whitespace/formatting differences ignored
below — only structural differences are described.

## 03-multiline-def — definition with a continuation line + a second paragraph
*How much multi-line content belongs to the `<dd>`?*
- **Ours:** only the **first line** goes in the `<dd>`. The continuation line and
  the second paragraph fall out of the `<dl>` as **raw, unrendered markdown**.
- **Pandoc:** folds the continuation line **into** the `<dd>` (lazy continuation),
  then **ejects** the second paragraph as a sibling `<p>` after `</dl>`.
- **Hugo:** keeps **everything inside** the `<dd>` — continuation line as text,
  second paragraph as a nested `<p>`.
- All three differ. We capture the least, Pandoc the middle, Hugo the most.

## 04-markdown-in-def — definition containing a bullet list (with a blockquote)
*What happens to the nested list?*
- **Ours:** intro line becomes the `<dd>`; the **entire bullet list falls out as
  raw markdown** (unrendered `- …` lines after `</dl>`).
- **Pandoc:** bullets **flattened into the `<dd>`** as inline text — no `<ul>`, the
  `-` become literal dashes.
- **Hugo:** bullets become a **real nested `<ul>`/`<li>`** (blockquote and all)
  inside the `<dd>`.
- All three differ; same shape as 03. We drop it, Pandoc absorbs-but-flattens,
  Hugo builds true structure.

## 05-nested — a definition list nested under another definition
*Nest or flatten?*
- **Ours:** **flatten** — one flat `<dl>`; "Inner Term" is just another `<dt>`.
- **Pandoc:** **flatten** — structurally **identical to ours**.
- **Hugo:** **nests** a real inner `<dl>` inside the outer `<dd>`.
- Ours == Pandoc; Hugo is the odd one out.

## 07-extra-space — term then a 2-space-indented `: Definition`
*Is a 2-space colon a definition marker?*
- **Ours:** **yes** → clean `<dl>`.
- **Pandoc:** **yes** → structurally **identical to ours**.
- **Hugo:** **no** → rejects it, emits a plain `<p>`.
- Ours == Pandoc; Hugo is the odd one out.

## Pattern

Two clean groups:

- **Marker / flattening decisions (05, 07):** we land **exactly on Pandoc**. These
  are the calls our CommonMark-marker + flat-inline design makes cleanly; Pandoc
  agrees, Hugo diverges (nests / stricter marker).
- **Block-content-in-a-definition (03, 04):** we diverge from **both** tools, doing
  **less** — we emit the `<dl>` for the term/first line and let the rest fall
  through as raw markdown, rather than absorbing it into the `<dd>` (flattened like
  Pandoc, or structured like Hugo).

In short: our behavior is **"Pandoc, minus the ability to pull block content into
a `<dd>`."** Single inline-line definitions (01, 02, 05, 07, 08, 09) match a real
engine; genuinely multi-block definitions (03, 04) stop at the first line and pass
the remainder through. Closing that gap is what Option B would entail.
