# Warning Counter Plan

## Goal

When the same warning fires multiple times across a single page render, show it once with a `[×N]` count prefix instead of N identical diagnostic blocks.

```
[×5] first -3 is equivalent to last 3 — consider using the clearer form
 --> layouts/home.html:12:1
  |
12 | <ul>{{#items | first -3}}<li>{{.}}</li>{{/items}}</ul>
   | ^^^^^^^^^^^^^^^^^^^^^ consider using the clearer form
   |
```

## Approach

Module-level buffer in `pipes.odin`. Warnings are collected during render, deduplicated + counted + logged after the page completes. No parameter threading through `render_nodes`.

## Changes

### `mustache/pipes.odin`

**New module-level state:**
```odin
_pending_warnings: [dynamic]Error
```

**New procs:**
```odin
reset_warnings :: proc() {
    clear(&_pending_warnings)
}

flush_warnings :: proc(colorize: bool = false) {
    if len(_pending_warnings) == 0 do return

    counts := make(map[string]int, context.temp_allocator)
    first: map[string]Error = make(map[string]Error, context.temp_allocator)
    defer delete(counts)
    defer delete(first)

    for w in _pending_warnings {
        b := body(w)
        if _, seen := first[b.msg]; !seen {
            first[b.msg] = w
        }
        counts[b.msg] += 1
    }

    for msg, w in first {
        c := counts[msg]
        b := body(w)
        path := b.path != "" ? b.path : "<input>"
        prefix := c > 1 ? fmt.tprintf("[×%d] ", c) : ""
        diag := diags.format_error(
            path, b.source, b.pos, b.msg,
            hint = b.hint,
            colorize = colorize,
        )
        log.warnf("%s%s", prefix, diag)
    }

    clear(&_pending_warnings)
}
```

**`apply_pipeline` change:**

Replace the current warning handling (which logs immediately):
```odin
if warnings != nil {
    append(warnings, ferr)
} else {
    log.warnf("%s", format_render_error(ferr, tmpl))
}
```

With:
```odin
append(&_pending_warnings, ferr)
```

Drop the `warnings: ^[dynamic]Error` parameter — no longer needed.

### `render.odin`

In `render_template`, wrap the render call:
```odin
mustache.reset_warnings()
result, err := mustache.render(content_tpl, []any{ctx.site, ctx.page, ctx}, partials)
mustache.flush_warnings(colorize = diags.should_colorize())
```

### `mustache/pipes.odin` cleanup

- Remove `warnings` parameter from `apply_pipeline` signature
- Remove `format_render_error` import/call from `apply_pipeline` (formatting moves to `flush_warnings`)
- Remove the `log` import if no longer used directly in `apply_pipeline`

## Scope

~25 lines new code (`reset_warnings` + `flush_warnings`), ~3 lines changed in `apply_pipeline`, ~2 lines added in `render.odin`. Total ~30 lines.

## Limitations

- Module-level state means warnings don't survive across page renders (by design — `reset_warnings` is called per page)
- Not thread-safe (fine for sequential rendering)
- Counting is by exact `msg` string — warnings with different messages but same root cause are counted separately
