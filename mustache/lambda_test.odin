#+test
package mustache

import "core:fmt"
import "core:testing"

// --- Spec test 1: Interpolation ---
// A lambda's return value should be interpolated.

Interp_Data :: struct {
	lambda: proc() -> string,
	planet: string,
}

Interp_Data_Int :: struct {
	lambda: proc() -> int,
	planet: string,
}

@(test)
test_lambda_interpolation :: proc(t: ^testing.T) {
	data := Interp_Data {
		lambda = proc() -> string {return "world"},
	}
	tpl, _ := parse("Hello, {{lambda}}!", context.temp_allocator)
	result, _ := render(tpl, data, allocator = context.temp_allocator)
	testing.expect_value(t, result, "Hello, world!")
}

// --- Spec test 2: Interpolation - Expansion ---
// A lambda's return value should be parsed.

@(test)
test_lambda_interpolation_expansion :: proc(t: ^testing.T) {
	data := Interp_Data {
		lambda = proc() -> string {return "{{planet}}"},
		planet = "world",
	}
	tpl, _ := parse("Hello, {{lambda}}!", context.temp_allocator)
	result, _ := render(tpl, data, allocator = context.temp_allocator)
	testing.expect_value(t, result, "Hello, world!")
}

// --- Spec test 4: Interpolation - Multiple Calls ---
// Interpolated lambdas should not be cached.

counter_lambda :: proc() -> int {
	@(static) call_count := 0
	call_count += 1
	return call_count
}

@(test)
test_lambda_interpolation_multiple_calls :: proc(t: ^testing.T) {
	data := Interp_Data_Int {
		lambda = counter_lambda,
	}
	tpl, _ := parse("{{lambda}} == {{{lambda}}} == {{lambda}}", context.temp_allocator)
	result, _ := render(tpl, data, allocator = context.temp_allocator)
	testing.expect_value(t, result, "1 == 2 == 3")
}

// --- Spec test 5: Escaping ---
// Lambda results should be appropriately escaped.

@(test)
test_lambda_escaping :: proc(t: ^testing.T) {
	data := Interp_Data {
		lambda = proc() -> string {return ">"},
	}
	tpl, _ := parse("<{{lambda}}{{{lambda}}}", context.temp_allocator)
	result, _ := render(tpl, data, allocator = context.temp_allocator)
	testing.expect_value(t, result, "<&gt;>")
}

// --- Spec test 6: Section ---
// Lambdas used for sections should receive the raw section string.

Section_Data :: struct {
	lambda: proc(_: string) -> string,
	x:      string,
	planet: string,
}

@(test)
test_lambda_section :: proc(t: ^testing.T) {
	data := Section_Data {
		lambda = proc(text: string) -> string {
			if text == "{{x}}" {return "yes"} else {return "no"}
		},
		x = "Error!",
	}
	tpl, _ := parse("<{{#lambda}}{{x}}{{/lambda}}>", context.temp_allocator)
	result, _ := render(tpl, data, allocator = context.temp_allocator)
	testing.expect_value(t, result, "<yes>")
}

// --- Spec test 7: Section - Expansion ---
// Lambdas used for sections should have their results parsed.

@(test)
test_lambda_section_expansion :: proc(t: ^testing.T) {
	data := Section_Data {
		lambda = proc(text: string) -> string {
			return fmt.tprintf("%s{{{{planet}}}}%s", text, text)
		},
		planet = "Earth",
	}
	tpl, _ := parse("<{{#lambda}}-{{/lambda}}>", context.temp_allocator)
	result, _ := render(tpl, data, allocator = context.temp_allocator)
	testing.expect_value(t, result, "<-Earth->")
}

// --- Spec test 9: Section - Multiple Calls ---
// Lambdas used for sections should not be cached.

@(test)
test_lambda_section_multiple_calls :: proc(t: ^testing.T) {
	data := Section_Data {
		lambda = proc(text: string) -> string {
			return fmt.tprintf("__%s__", text)
		},
	}
	tpl, _ := parse("{{#lambda}}FILE{{/lambda}} != {{#lambda}}LINE{{/lambda}}", context.temp_allocator)
	result, _ := render(tpl, data, allocator = context.temp_allocator)
	testing.expect_value(t, result, "__FILE__ != __LINE__")
}

// --- Spec test 10: Inverted Section ---
// Lambdas used for inverted sections should be considered truthy.

Inverted_Data :: struct {
	lambda: proc(_: string) -> bool,
	static: string,
}

@(test)
test_lambda_inverted_section :: proc(t: ^testing.T) {
	data := Inverted_Data {
		lambda = proc(text: string) -> bool {return false},
		static = "static",
	}
	tpl, _ := parse("<{{^lambda}}{{static}}{{/lambda}}>", context.temp_allocator)
	result, _ := render(tpl, data, allocator = context.temp_allocator)
	testing.expect_value(t, result, "<>")
}

