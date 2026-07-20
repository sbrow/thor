#+test
package mustache

import "core:mem"
import "core:testing"

@(test)
leak_parse_free :: proc(t: ^testing.T) {
	tmpl, err := parse("Hello {{name}}!")
	testing.expect(t, err == nil)
	defer delete_template(&tmpl)
}

@(test)
leak_parse_free_tokens :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	backing: [256]byte
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	tmpl, err := parse("Hello {{name}}!", context.allocator, mem.dynamic_arena_allocator(&arena))
	testing.expect(t, err == nil)
	defer delete_template(&tmpl)
}

@(test)
leak_parse_error :: proc(t: ^testing.T) {
	tmpl, err := parse("Hello {{name")
	testing.expect(t, err != nil)
}

@(test)
leak_render :: proc(t: ^testing.T) {
	Data :: struct {
		name: string,
	}
	tmpl, err := parse("Hello {{name}}!")
	testing.expect(t, err == nil)
	defer delete_template(&tmpl)

	result, rerr := render(tmpl, Data{name = "World"})
	testing.expect(t, rerr == nil)
	defer delete(result)
}

@(test)
leak_render_partials :: proc(t: ^testing.T) {
	partials := make_map(map[string]Template)
	defer {
		for _, &p in partials {
			delete_template(&p)
		}
		delete(partials)
	}

	pt, perr := parse("world")
	testing.expect(t, perr == nil)
	partials["name"] = pt

	tmpl, err := parse("Hello {{> name}}!")
	testing.expect(t, err == nil)
	defer delete_template(&tmpl)

	Data :: struct {
		name: string,
	}
	result, rerr := render(tmpl, Data{name = "World"}, partials)
	testing.expect(t, rerr == nil)
	defer delete(result)
}

@(test)
leak_render_sections :: proc(t: ^testing.T) {
	tmpl, err := parse("{{#items}}{{.}}{{/items}}")
	testing.expect(t, err == nil)
	defer delete_template(&tmpl)

	Data :: struct {
		items: [3]string,
	}
	result, rerr := render(tmpl, Data{items = {"a", "b", "c"}})
	testing.expect(t, rerr == nil)
	defer delete(result)
}

@(test)
leak_render_inheritance :: proc(t: ^testing.T) {
	partials := make_map(map[string]Template)
	defer delete_partials(partials)

	layout_src := "{{$title}}default{{/title}}"
	layout, lerr := parse(layout_src)
	testing.expect(t, lerr == nil)
	partials["layout"] = layout

	tmpl_src := "{{<layout}}{{$title}}custom{{/title}}{{/layout}}"
	tmpl, err := parse(tmpl_src)
	testing.expect(t, err == nil)
	defer delete_template(&tmpl)

	result, rerr := render(tmpl, {}, partials)
	testing.expect(t, rerr == nil)
	defer delete(result)
}

@(test)
leak_repeated_render :: proc(t: ^testing.T) {
	tmpl, err := parse("Hello {{name}}!")
	testing.expect(t, err == nil)
	defer delete_template(&tmpl)

	Data :: struct {
		name: string,
	}
	for _ in 0 ..< 3 {
		result, rerr := render(tmpl, Data{name = "World"})
		testing.expect(t, rerr == nil)
		defer delete(result)
	}
}

