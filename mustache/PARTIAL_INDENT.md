# Partial Indentation — Problem & Solutions

## Problem

When a partial tag `{{> name}}` is standalone (only non-whitespace on its line), the mustache spec requires that its leading whitespace be treated as indentation and **prepended to each line of the partial source before rendering**.

This is a source-level transformation, not output post-processing. The distinction matters when interpolated content contains newlines:

```
partial source:  "|\n{{{content}}}\n|\n"
content value:   "<\n->"
indent:          " "

Expected output: " |\n <\n->\n |\n"
```

The line `->` gets NO indent — it comes from expanded content (`<\n->`), not from a partial source line. Post-processing the output would incorrectly indent it.

### Spec tests that require this

- **Standalone Without Previous Line** — indent at start of template
- **Standalone Without Newline** — indent at end of template
- **Standalone Indentation** — indent with multi-line interpolated content

3 of 14 tests in `partials.json`. The other 11 (basic lookup, context, recursion, nesting, inline usage, failed lookup, padding) work without indentation handling.

### thor's real usage

Thor's partials (`{{> nav}}`, `{{> footer}}`, `{{>* icon}}`) are typically standalone with indentation. Without indentation handling, HTML output has wrong indentation — ugly but functional since HTML ignores whitespace.

## Solution 1: Store source, re-parse with indent (Recommended)

Add `source: string` to `Template`. When rendering a standalone partial with non-empty indent:

1. Prepend indent to each line of `partial.source`
2. Re-tokenize + re-parse with `context.temp_allocator`
3. Render the re-parsed nodes

When indent is empty, render the pre-parsed nodes directly (no re-parse).

### Pros
- Correct by construction — exactly matches spec ("prepended to each line before rendering")
- ~20 lines of code
- Nested partials accumulate indentation naturally
- No line-start state tracking

### Cons
- Template gains a `source: string` field
- Standalone partials with indent get re-parsed at render time (negligible for small fragments)

### Implementation sketch

```odin
// tokenizer: capture indent during trim_standalone_whitespace
// for Partial tokens, before stripping left whitespace:
tokens[i].indent = text[nl+1:]  // capture indentation

// mustache.odin: Template gains source field
Template :: struct {
    nodes: [dynamic]Node,
    source: string,
}

// parse: store source
tmpl.source = source

// renderer: re-parse if indent
case .Partial:
    pt, found := partials[name]
    if !found do break
    if len(node.indent) > 0 {
        indented := indent_lines(pt.source, node.indent)
        reparse, err := parse(indented, context.temp_allocator, context.temp_allocator)
        if err == nil {
            defer delete(reparse.nodes)
            render_nodes(reparse.nodes[:], reparse.nodes[:], ctx, partials, b)
        }
    } else {
        render_nodes(pt.nodes[:], pt.nodes[:], ctx, partials, b)
    }
```

## Solution 2: Modify text nodes during rendering

Track "at line start" state while rendering the partial's nodes. Insert indent before text-node content that begins a new line. Variables/sections render normally — their output is NOT indented.

### Pros
- No source storage
- No re-parsing

### Cons
- Complex: must track line-start state across nodes
- Variables producing multi-line output need careful handling (their newlines don't create indented lines)
- Trailing newline edge case (partial ending with `\n` shouldn't leave trailing indent)
- Nested partials with accumulated indentation need extra logic
- ~60+ lines of fiddly code

### Implementation sketch

```odin
render_partial :: proc(nodes, ctx, partials, b, indent) {
    at_line_start := true
    for node in nodes {
        switch node.kind {
        case .Text:
            // Walk text, prepend indent at line starts
            // Insert indent after each \n
            // Don't indent after final \n of last text node
            ...
            at_line_start = (text ends with \n)
        case .Variable, .Unescaped:
            // Render normally — no indent applied to output
            write_value(b, val, ...)
            at_line_start = false  // can't know if output ends with \n
        case .Section, .Inverted:
            // Complex: nested text nodes need indent too?
            ...
        }
    }
}
```

The "can't know if variable output ends with \n" problem makes `at_line_start` unreliable, requiring heuristics or output buffering.

## Adjacent Tag Standalone Detection

**Problem:** When a block-type tag and its close tag are adjacent (no text between them), like `{{<include}}{{/include}}\n`, neither tag is individually detected as standalone. The current check looks at the immediately adjacent token — if it's another tag (not text), the check fails. So the trailing `\n` isn't consumed.

**Affected spec tests:**
- `~inheritance.json`: "Inherit", "Override parent with newlines"
- Potentially any `{{<name}}{{/name}}` or `{{#name}}{{/name}}` on its own line

**Solution:** When scanning left/right for the line boundary, skip over adjacent standalone-eligible tags (they're transparent). Two helper procs replace the current inline checks:
- `check_left(tokens, i)` — scans backwards through adjacent eligible tags until finding text or start of template
- `check_right(tokens, i)` — scans forwards through adjacent eligible tags until finding text or end of template

Both return `(ok: bool, text_idx: int)` where `text_idx` is the text token to trim (or -1 if none).
