# Plan: Computed Properties in Mustache

## Problem

`Year_Section` is a privileged, hardcoded struct in render.odin. Every section listing gets pages grouped by year — no choice. The grouping dimension (year) is baked into the code. Templates can't request different views of the same data.

## Solution: Computed Properties

Struct fields that are procs get called during mustache data resolution. When `lookup_in` resolves a field via reflection and finds a proc, it calls it and uses the return value. This is computed properties (Vue/Ember pattern), not spec lambdas (text transformers).

No mustache syntax changes. `{{#posts.by_year}}` is vanilla mustache — the magic is in data resolution, not template syntax.

## Template Usage

```handlebars
{{#posts.by_year}}
  <h2>{{year}}</h2>
  {{#posts}}
    <li>{{title}}</li>
  {{/posts}}
{{/posts.by_year}}

{{#posts.all}}
  <li>{{title}}</li>
{{/posts.all}}
```

Context resolution handles naming naturally — `posts` inside a Year_Group (the `.posts` field) shadows the outer `posts` view object.

## Data Model

```odin
Year_Group :: struct {
    year:  string,
    posts: [dynamic]Page_Context,
}

Pages_View :: struct {
    all:     [dynamic]Page_Context,
    by_year: proc() -> [dynamic]Year_Group,
}

Section_Data :: struct {
    using base: Base_Data,
    page_title: string,
    posts:      Pages_View,
}
```

`by_year` is a closure that captures `all` and groups lazily. Grouping only happens when the template requests it.

## Implementation Steps

### 1. Mustache data layer (`mustache/data.odin`)

In `lookup_in` (or `resolve_name`), after resolving a field value via reflection:

```odin
// If the resolved value is a proc, call it
if value, ok := resolved.(proc() -> any); ok {
    return value()
}
```

Need to handle proc detection generically — Odin has many proc types (different signatures, calling conventions). The computed properties we use are all zero-argument procs returning `any`.

Alternative: check via `reflect.Type_Info` if the value is a proc type, then call it through `reflect.CallProcedure` or transmute.

### 2. Odin closure challenge

Contextless procs can't capture variables. Regular closure procs capture context by reference. We need the proc to access the page list when called later by mustache.

Options:
- Store the data alongside the proc in the struct (e.g., `all` field on `Pages_View`). The proc accesses it via the struct instance.
- Use `context.allocator` to store captured data that the closure references.
- Pass the struct as an implicit `self` parameter (method-style).

The simplest approach: the closure captures a pointer to the data, which is arena-allocated and alive during rendering.

### 3. Build `Pages_View` in `render_section`

```odin
all_pages := make([dynamic]Page_Context)
for page in site.pages {
    if page.section != section || page._is_index { continue }
    append(&all_pages, build_page_context(page))
}

view := Pages_View{
    all = all_pages,
    by_year = group_by_year_closure,  // captures all_pages
}
```

### 4. Remove `Year_Section` and `year_sections`

- Delete `Year_Section` struct
- Remove `year_sections` from `Section_Data`
- Remove year grouping logic from `render_section`
- Delete `get_year` helper (or move it into the closure)

### 5. Update templates

`posts_index.html`:
```handlebars
{{#posts.by_year}}
  <section>
    <h2>{{year}}</h2>
    <ul class="post-list">
      {{#posts}} <li>...</li> {{/posts}}
    </ul>
  </section>
{{/posts.by_year}}
```

Home page could use the same pattern:
```handlebars
{{#pages.all}}
  <li>...</li>
{{/pages.all}}
```

### 6. Tests

- Verify `by_year` proc is called lazily (only when template requests it)
- Verify year groups contain correct pages
- Verify flat list (`all`) works independently

## Prerequisite

**Step 1 (mustache data layer) must be done first.** This is the foundation — without proc-calling in data resolution, none of the rest works.

## Future Extensions

Once computed properties work, they're available everywhere:
- `posts.featured` — filter by starred
- `posts.recent(n)` — most recent N posts (if we support params)
- `site.tags` — all unique tags across posts
- `pages.by_section("posts")` — filter by section

These are all zero-argument procs on view structs. No mustache changes needed beyond step 1.
