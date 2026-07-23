# Mustache Extensions

Thor's mustache engine implements the [Mustache spec](https://github.com/mustache/spec) plus the following non-standard extensions. Extensions are opt-in via template syntax — vanilla mustache templates render identically to the spec.

## Pipes

A pipe expression appears inside a section tag or an interpolation tag and transforms the resolved value before rendering. Pipes let templates request different views of the same data without privileged Go-side support.

### Syntax

```
{{#<key> | <op> <arg> <arg>... | <op> <arg>... }} … {{/<key>}}
{{<key> | <op> <arg> <arg>... | <op> <arg>...}}
```

- The first whitespace-separated token after `|` is the op name; remaining tokens are its arguments.
- Whitespace around `|` is optional: `posts|group_by year` and `posts | group_by year` are equivalent.
- Multiple filters compose left-to-right.
- **At most 8 filters** may appear in a single tag (compile-time constant `MAX_PIPES` in `pipes.odin`). Exceeding it is a parse error.
- **At most 2 args** per filter (compile-time constant `MAX_PIPE_ARGS`). Exceeding it is a parse error.
- The close tag is the **bare key only**. Pipe expressions are not allowed in close tags — `{{/posts | group_by year}}` is a parse error.
- Pipes work in both section tags (`{{#…}}` and `{{^…}}`) and interpolation tags (`{{…}}` and `{{&…}}`). In sections, the transformed value becomes the section's context. In interpolations, the transformed value is what gets rendered.

### Example

```handlebars
{{#posts | group_by year}}
  <section>
    <h2>{{key}}</h2>
    <ul>{{#items}}<li>{{title}}</li>{{/items}}</ul>
  </section>
{{/posts}}

<!-- Interpolation pipe: format a date string for display -->
<time datetime="{{date}}">{{date | format}}</time>
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

#### `format`

Formats an ISO 8601 date string as a display string. Takes a string, returns a string (e.g. `"2026-03-15T08:49:54-04:00"` → `"15 Mar 2026"`). Invalid input (empty, too-short, non-string, or unparseable) returns a `Data_Error`. Templates that need to skip dateless pages should gate with a section — `{{#date}}<time datetime="{{.}}">{{. | format}}</time>{{/date}}` — so the section's truthiness check catches empty before the filter runs. Commonly used inline as `{{date | format}}` to render a display string while keeping the raw ISO available via `{{date}}` for the `datetime=` attribute.

Internally: parses the invariant `YYYY-MM-DD` prefix by char offset, stringifies `time.Month(month_num)` and slices `[:3]` for the abbreviation. Accepts any of these ISO 8601 forms (the date prefix is what matters): `2023-10-15T13:18:50-07:00`, `2023-10-15T13:18:50-0700`, `2023-10-15T13:18:50Z`, `2023-10-15T13:18:50`, `2023-10-15`.

Takes an optional arg for the Go reference-date layout to use:
- A double-quoted literal, spaces allowed: `{{date | format "Mon Jan 2 2006"}}`.
- A bare key, resolved from context like any other field: `{{date | format long}}` uses the value of `long` (e.g. a site-config field) as the layout.
- No arg: falls back to the `date_format` context key (typically `date.format` from `thor.json`).

### Memory ownership

- **Parsed pipe filters** (`Pipe_Filter` values) are stored inline on each `Node` via `[dynamic; MAX_PIPES]Pipe_Filter`, and `args` is inline on each `Pipe_Filter` via `[dynamic; MAX_PIPE_ARGS]string`. Both use Odin's fixed-capacity dynamic array type, so no per-tag heap allocations occur at parse time. The storage dies with the `Template` when `delete_template` is called.
- **Filter results** (e.g. the `[dynamic]Group` returned by `group_by`, or the display string returned by `format`) are render-scoped allocations in `context.temp_allocator`. They die with the render call. No caller-side cleanup is needed.
- The string data inside `Pipe_Filter` (op names, args) is borrowed from the template source — no cloning.


