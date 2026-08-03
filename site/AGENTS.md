# Docs Site AGENTS.md

## DO NOT EDIT — BY HUMANS, FOR HUMANS

All content under `thor/site/` is handwritten by humans. No AI, agent,
bot, or assistant may edit, rewrite, or generate any file here. AI may
be consulted as a sanity check, but the prose stays human.

## Implicit limits

The mustache engine imposes limits that template authors should be aware of.
These values are defined in `thor/mustache/pipes.odin`, and `thor/mustache/mustache.odin`
and must be kept in sync with the source code if they ever change.

- **Nested partials** — deeply nested partial chains (partial-in-partial)
  consume context stack frames during rendering. The limit is defined by
  `MAX_CONTEXT_STACK` (16) in the mustache engine. In practice, 3–4 levels of
  nesting is typical and safe.

- **`MAX_PIPES` (8)** — a single tag may chain up to 8 pipe filters:
  `{{key | op1 | op2 | ... | op8}}`. Exceeding this is a parse error.

- **`MAX_PIPE_ARGS` (2)** — each pipe filter accepts at most 2 arguments:
  `{{key | op arg1 arg2}}`.
