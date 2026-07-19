package mustache

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"

// base_value unwraps union variants and strips Named/Distinct layers,
// returning the "peeled" any value and its base type info.
base_value :: proc(a: any) -> (val: any, info: ^runtime.Type_Info) {
	if a == nil {
		return
	}

	val = a
	info = nil

	ti := type_info_of(val.id)
	if ti == nil {
		return
	}

	base := runtime.type_info_base(ti)

	if _, ok := base.variant.(runtime.Type_Info_Union); ok {
		variant := reflect.get_union_variant(val)
		if variant == nil {
			return {}, nil
		} else {
			return base_value(variant)
		}
	}

	info = base
	return
}

// lookup_in resolves a single key in a container (struct or map).
// Returns found=false if the key doesn't exist or the container is not a struct/map.
lookup_in :: proc(container: any, key: string) -> (result: any, found: bool) {
	if container == nil {
		return
	}

	val, info := base_value(container)
	if info == nil {
		return
	}

	#partial switch v in info.variant {
	case runtime.Type_Info_Struct:
		result = reflect.struct_field_value_by_name(val, key, allow_using = true)
		found = result != nil
	case runtime.Type_Info_Map:
		mi := v
		rm_ptr := (^runtime.Raw_Map)(val.data)
		if rm_ptr.len == 0 {
			return
		}

		k := key
		seed := runtime.map_seed(rm_ptr^)
		h := mi.map_info.key_hasher(&k, seed)
		value_ptr := runtime.__dynamic_map_get(rm_ptr, mi.map_info, h, &k)
		if value_ptr != nil {
			if _, ok := mi.value.variant.(runtime.Type_Info_Any); ok {
				result = (^any)(value_ptr)^
			} else {
				result = any{value_ptr, mi.value.id}
			}
			found = true
		}
	}

	return
}

// resolve_name resolves a (possibly dotted) name from the context stack.
// The first segment walks the stack top-to-bottom; remaining segments
// resolve against the prior result only.
resolve_name :: proc(name: string, ctx: []any) -> any {
	if name == "." {
		if len(ctx) > 0 {
			return ctx[len(ctx) - 1]
		} else {
			return nil
		}
	}

	parts: [16]string
	part_count := 0
	start := 0
	for i in 0 ..< len(name) {
		if name[i] == '.' {
			if part_count < len(parts) {
				parts[part_count] = name[start:i]
				part_count += 1
			}
			start = i + 1
		}
	}
	if part_count < len(parts) {
		parts[part_count] = name[start:]
		part_count += 1
	}

	if part_count == 0 {
		return nil
	}

	dot_parts := parts[:part_count]

	result: any = nil
	found := false
	for i := len(ctx) - 1; i >= 0; i -= 1 {
		result, found = lookup_in(ctx[i], dot_parts[0])
		if found {
			break
		}
	}

	if !found {
		return nil
	}
	if len(dot_parts) == 1 {
		return result
	}

	for i := 1; i < len(dot_parts); i += 1 {
		result, found = lookup_in(result, dot_parts[i])
		if !found {
			return nil
		}
	}

	return result
}

// is_truthy checks mustache truthiness.
is_truthy :: proc(a: any) -> bool {
	if a == nil {
		return false
	}

	val, info := base_value(a)
	if info == nil {
		return false
	}
	if reflect.is_nil(val) {
		return false
	}

	#partial switch _ in info.variant {
	case runtime.Type_Info_Slice, runtime.Type_Info_Dynamic_Array, runtime.Type_Info_Map:
		return reflect.length(val) > 0
	case:
		return true
	}
}

call_interp_lambda :: proc(val: any) -> (result: string, ok: bool) {
	switch v in val {
	case proc() -> string:
		return v(), true
	case proc() -> int:
		return fmt.tprintf("%d", v()), true
	case proc() -> bool:
		return "true" if v() else "false", true
	case:
		return "", false
	}
}

call_section_lambda :: proc(val: any, text: string) -> (result: string, ok: bool) {
	switch v in val {
	case proc(string) -> string:
		return v(text), true
	case proc(string) -> int:
		return fmt.tprintf("%d", v(text)), true
	case proc(string) -> bool:
		return "true" if v(text) else "false", true
	case:
		return "", false
	}
}

// list_info returns element type info, count, and data pointer for a list value.
// Returns elem_info=nil if the value is not a list.
list_info :: proc(a: any) -> (elem_info: ^runtime.Type_Info, count: int, data: rawptr) {
	val, info := base_value(a)
	if info == nil {
		return
	}

	#partial switch v in info.variant {
	case runtime.Type_Info_Slice:
		raw := (^runtime.Raw_Slice)(val.data)^
		return v.elem, raw.len, raw.data
	case runtime.Type_Info_Dynamic_Array:
		raw := (^runtime.Raw_Dynamic_Array)(val.data)^
		return v.elem, raw.len, raw.data
	case runtime.Type_Info_Array:
		return v.elem, v.count, val.data
	case:
		return nil, 0, nil
	}
}

// any_to_string converts a scalar value to a string using the temp allocator.
any_to_string :: proc(a: any) -> string {
	if a == nil {
		return ""
	}
	val, _ := base_value(a)

	switch v in val {
	case string:
		return v
	case bool:
		return "true" if v else "false"
	case i64:
		return fmt.tprintf("%d", v)
	case f64:
		// return fmt.tprintf("%.3f", v)
		return format_f64(v)
	case int:
		return fmt.tprintf("%d", v)
	case:
		return ""
	}
}

// format_f64 produces the shortest string that round-trips to the same f64.
// Works around Odin's strconv not implementing shortest representation.
format_f64 :: proc(v: f64) -> string {
	buf: [64]byte
	for prec in 1 ..= 17 {
		s := strconv.write_float(buf[:], v, 'g', prec, 64)
		if len(s) > 0 && s[0] == '+' {
			s = s[1:]
		}
		parsed, ok := strconv.parse_f64(s)
		if ok && parsed == v {
			return strings.clone(s, context.temp_allocator)
		}
	}
	s := strconv.write_float(buf[:], v, 'g', -1, 64)
	if len(s) > 0 && s[0] == '+' {
		s = s[1:]
	}
	return strings.clone(s, context.temp_allocator)
}

// write_value stringifies a value and writes it to the builder,
// optionally HTML-escaped.
write_value :: proc(b: ^strings.Builder, a: any, escape: bool) {
	s := any_to_string(a)
	if len(s) == 0 {
		return
	}

	if !escape {
		strings.write_string(b, s)
		return
	}

	start := 0
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&', '<', '>', '"':
			if i > start {
				strings.write_string(b, s[start:i])
			}
			switch s[i] {
			case '&':
				strings.write_string(b, "&amp;")
			case '<':
				strings.write_string(b, "&lt;")
			case '>':
				strings.write_string(b, "&gt;")
			case '"':
				strings.write_string(b, "&quot;")
			}
			start = i + 1
		}
	}
	if start < len(s) {
		strings.write_string(b, s[start:])
	}
}

