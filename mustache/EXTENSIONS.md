# Mustache Extensions

Thor's mustache engine implements the [Mustache spec](https://github.com/mustache/spec) plus the following non-standard extensions. Extensions are opt-in via template syntax — vanilla mustache templates render identically to the spec.

## Pipes

A pipe expression appears inside a section tag and transforms the resolved value before iteration. Pipes let templates request different views of the same data without privileged Go-side support.

### Syntax

```
{{#<key> | <op> <arg> <arg>... | <op> <arg>... }} … {{/<key>}}
```

- The first whitespace-separated token after `|` is the op name; remaining tokens are its arguments.
- Whitespace around `|` is optional: `posts|group_by year` and `posts | group_by year` are equivalent.
- Multiple filters compose left-to-right.
- **At most 8 filters** may appear in a single tag (compile-time constant `MAX_PIPES` in `pipes.odin`). Exceeding it is a parse error.
- **At most 2 args** per filter (compile-time constant `MAX_PIPE_ARGS`). Exceeding it is a parse error.
- The close tag is the **bare key only**. Pipe expressions are not allowed in close tags — `{{/posts | group_by year}}` is a parse error.
- Pipes are only supported in section tags (`{{#…}}` and `{{^…}}`) today. Variable interpolation (`{{x | op}}`) is a parse error.

### Example

```handlebars
{{#posts | group_by year}}
  <section>
    <h2>{{key}}</h2>
    <ul>{{#items}}<li>{{title}}</li>{{/items}}</ul>
  </section>
{{/posts}}
```

### Available ops

#### `group_by <field>`

Buckets each element of a list by the value of `<field>`. Returns a list of `Group` values, each shaped as:

```
Group :: struct {
    key:   string,   // the distinct field value
    items: [dynamic]any,  // elements sharing that value
}
```

Group order preserves first-appearance order in the input list (not key-sorted).

Errors (returned as `Data_Error` at render time):
- Argument count is not 1.
- Input is not a list.
- Any element is missing the named field.
- Any element has an empty value for the named field.

### Memory ownership

- **Parsed pipe filters** (`Pipe_Filter` values) are stored inline on each `Node` via `[dynamic; MAX_PIPES]Pipe_Filter`, and `args` is inline on each `Pipe_Filter` via `[dynamic; MAX_PIPE_ARGS]string`. Both use Odin's fixed-capacity dynamic array type, so no per-tag heap allocations occur at parse time. The storage dies with the `Template` when `delete_template` is called.
- **Filter results** (e.g. the `[dynamic]Group` returned by `group_by`) are render-scoped allocations in `context.temp_allocator`. They die with the render call. No caller-side cleanup is needed.
- The string data inside `Pipe_Filter` (op names, args) is borrowed from the template source — no cloning.

### Future ops (not yet implemented)

The pipe framework is general; additional ops are straightforward to add to `apply_filter` in `pipes.odin`:

- `sort`, `sort_by <field>` — ordering
- `filter <field> <value>`, `where <field>` — selection
- `take <n>`, `take_last <n>`, `skip <n>` — slicing
- `reverse` — order flip

To add a new op:
1. Implement `apply_<op>(value: any, args: []string) -> (any, Render_Error)` in `pipes.odin`.
2. Add a `case` to `apply_filter`.
3. Add tests to `pipes_test.odin`.
