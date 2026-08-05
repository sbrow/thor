#+test
#+feature dynamic-literals
package mustache

import "core:encoding/json"
import "core:fmt"
import "core:testing"

import diags "../diagnostics"

Inner :: struct {
	foo: string,
	bar: int,
}

Page :: struct {
	title: string,
}

Outer :: struct {
	title:   string,
	page:    Page,
	inner:   Inner,
	numbers: [3]int,
}

@(test)
test_validate_simple_found :: proc(t: ^testing.T) {
	data := Outer {
		title = "hi",
	}
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	ok, missing, _ := validate_key_path(ctx[:], "title")
	testing.expect_value(t, ok, true)
	testing.expect(t, missing == "", fmt.tprintf("expected empty missing, got %q", missing))
}

@(test)
test_validate_simple_missing :: proc(t: ^testing.T) {
	data := Outer {
		title = "hi",
	}
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	ok, missing, available := validate_key_path(ctx[:], "page_titel")
	testing.expect_value(t, ok, false)
	testing.expect_value(t, missing, "page_titel")
	testing.expect(t, len(available) > 0, "should have suggestions")
}

@(test)
test_validate_dotted_found :: proc(t: ^testing.T) {
	data := Outer {
		inner = Inner{foo = "x"},
	}
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	ok, missing, _ := validate_key_path(ctx[:], "inner.foo")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, missing, "")
}

@(test)
test_validate_dotted_missing :: proc(t: ^testing.T) {
	data := Outer {
		inner = Inner{foo = "x"},
	}
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	ok, missing, available := validate_key_path(ctx[:], "inner.fooo")
	testing.expect_value(t, ok, false)
	testing.expect_value(t, missing, "fooo")
	testing.expect(t, len(available) > 0, "should have inner field suggestions")
}

Params_Data :: struct {
	params: map[string]string,
}

Maybe_Bool_Data :: struct {
	flag: Maybe(bool),
	name: string,
}

Inner_For_Using :: struct {
	flag:  Maybe(bool),
	label: string,
}

Outer_With_Using :: struct {
	using inner: Inner_For_Using,
	other:       int,
}

@(test)
test_validate_path_through_using_to_maybe_bool :: proc(t: ^testing.T) {
	data := Outer_With_Using {
		inner = Inner_For_Using{label = "hi"},
		other = 42,
	}
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	// `flag` is promoted via using; field exists even when Maybe is nil.
	ok, missing, _ := validate_key_path(ctx[:], "flag")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, missing, "")

	// `label` is also promoted via using.
	ok2, missing2, _ := validate_key_path(ctx[:], "label")
	testing.expect_value(t, ok2, true)
	testing.expect_value(t, missing2, "")
}

@(test)
test_struct_has_field_with_maybe_bool :: proc(t: ^testing.T) {
	data := Maybe_Bool_Data {
		name = "hi",
	} // flag is nil Maybe
	testing.expect_value(t, struct_has_field(data, "flag"), true)
	testing.expect_value(t, struct_has_field(data, "name"), true)
	testing.expect_value(t, struct_has_field(data, "missing"), false)
}

@(test)
test_validate_path_through_maybe_bool :: proc(t: ^testing.T) {
	data := Maybe_Bool_Data {
		name = "hi",
	}
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	// `flag` exists as a field even when its Maybe value is nil — should NOT warn.
	ok, missing, _ := validate_key_path(ctx[:], "flag")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, missing, "")
}

@(test)
test_validate_map_path_silent :: proc(t: ^testing.T) {
	data := Params_Data {
		params = {"social" = "x"},
	}
	defer delete(data.params)
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	// `params` exists and is a map — subsequent segments are user-defined.
	ok, _, _ := validate_key_path(ctx[:], "params.anything_here")
	testing.expect_value(t, ok, true)
}

@(test)
test_warn_no_false_positive_for_valid_keys :: proc(t: ^testing.T) {
	Data :: struct {
		name: string,
	}
	src := "Hello {{name}}"
	tmpl, err := parse(src, "<test>", context.temp_allocator)
	testing.expect(t, err == nil, "should parse")
	if err != nil {
		return
	}

	// We can't easily capture log output in tests, but we can verify the
	// validation procs agree the key exists.
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, Data{name = "World"})

	ok, missing, _ := validate_key_path(ctx[:], "name")
	testing.expect_value(t, ok, true)
}

// --- json.Value map crossing tests ---

JSON_Params_Context :: struct {
	params: json.Value,
}

@(test)
test_validate_key_path_crosses_json_value_map :: proc(t: ^testing.T) {
	params_map := make(json.Object, context.temp_allocator)
	params_map["author"] = json.String("Tester")

	data := JSON_Params_Context { params = params_map }
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	ok, missing, _ := validate_key_path(ctx[:], "params.starred")
	testing.expect(t, ok, "path crossing json.Value map should be ok")
	testing.expect(t, missing == "", "no missing segment for map crossing")
}

@(test)
test_validate_key_path_json_value_map_existing_key :: proc(t: ^testing.T) {
	params_map := make(json.Object, context.temp_allocator)
	params_map["author"] = json.String("Tester")

	data := JSON_Params_Context { params = params_map }
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	ok, missing, _ := validate_key_path(ctx[:], "params.author")
	testing.expect(t, ok, "existing key in json.Value map should be ok")
}

@(test)
test_validate_key_path_map_typo :: proc(t: ^testing.T) {
	params_map := make(json.Object, context.temp_allocator)
	params_map["author"] = json.String("Tester")
	params_map["social"] = json.String("")

	data := JSON_Params_Context { params = params_map }
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	ok, missing, available := validate_key_path(ctx[:], "params.authr")
	testing.expect(t, !ok, "typo of map key should not be ok")
	testing.expect_value(t, missing, "authr")
	suggestion := diags.suggest_correction(available, "authr")
	testing.expect_value(t, suggestion, "author")
}

@(test)
test_validate_key_path_map_no_close_match :: proc(t: ^testing.T) {
	params_map := make(json.Object, context.temp_allocator)
	params_map["author"] = json.String("Tester")
	params_map["social"] = json.String("")

	data := JSON_Params_Context { params = params_map }
	ctx := make([dynamic]any, 0, 1, context.temp_allocator)
	append(&ctx, data)

	ok, missing, _ := validate_key_path(ctx[:], "params.xyz")
	testing.expect(t, ok, "unknown key with no close match should be ok (suppressed)")
	testing.expect(t, missing == "", "no missing segment when suppressed")
}
