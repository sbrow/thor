#+test
package mustache

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

run_spec_file :: proc(t: ^testing.T, path: string) {
	dirs := [?]string{#directory, path}
	path, _ := filepath.join(dirs[:], context.temp_allocator)
	raw_data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		testing.expectf(t, false, "Failed to read %s", path)
		return
	}
	defer delete(raw_data)

	value, jerr := json.parse(raw_data)
	if jerr != .None {
		testing.expectf(t, false, "JSON parse error in %s: %v", path, jerr)
		return
	}
	defer json.destroy_value(value)

	root := value.(json.Object)
	tests := root["tests"].(json.Array)

	passed := 0
	failed := 0

	for tv in tests {
		test := tv.(json.Object)
		name := test["name"].(string)
		template_src := test["template"].(string)
		expected := test["expected"].(string)

		if run_one_test(t, test, name, template_src, expected) {
			passed += 1
		} else {
			failed += 1
		}
	}

	if failed > 0 {
		testing.fail(t)
	}
	fmt.printfln("  %s: %d/%d passed", path, passed, passed + failed)
}

run_one_test :: proc(
	t: ^testing.T,
	test: json.Object,
	name, template_src, expected: string,
) -> bool {
	partials := make_map(map[string]Template, context.temp_allocator)

	if "partials" in test {
		p_obj, ok := test["partials"].(json.Object)
		assert(ok)
		for pname, pval in p_obj {
			psrc, ok := pval.(string)
			assert(ok)

			pt, perr := parse(psrc, context.temp_allocator)
			if perr != nil {
				testing.expectf(t, false, "[%s] partial '%s' parse error", name, pname)
				return false
			}
			partials[pname] = pt
		}
	}

	tmpl, terr := parse(template_src, context.temp_allocator)
	if terr != nil {
		testing.expectf(t, false, "[%s] template parse error", name)
		return false
	}
	defer delete(tmpl.nodes)

	result, rerr := render(tmpl, test["data"], partials)
	if rerr != nil {
		testing.expectf(t, false, "[%s] render error", name)
		return false
	}
	defer delete(result)

	if result != expected {
		testing.expectf(t, false, "[%s]\n  got:      %q\n  expected: %q", name, result, expected)
		return false
	}
	return true
}

@(test)
spec_interpolation :: proc(t: ^testing.T) {
	run_spec_file(t, "spec/specs/interpolation.json")
}

@(test)
spec_sections :: proc(t: ^testing.T) {
	run_spec_file(t, "spec/specs/sections.json")
}

@(test)
spec_inverted :: proc(t: ^testing.T) {
	run_spec_file(t, "spec/specs/inverted.json")
}

@(test)
spec_comments :: proc(t: ^testing.T) {
	run_spec_file(t, "spec/specs/comments.json")
}

@(test)
spec_partials :: proc(t: ^testing.T) {
	run_spec_file(t, "spec/specs/partials.json")
}

@(test)
spec_dynamic_names :: proc(t: ^testing.T) {
	run_spec_file(t, "spec/specs/dynamic-names.json")
}

@(test)
spec_inheritance :: proc(t: ^testing.T) {
	run_spec_file(t, "spec/specs/~inheritance.json")
}

