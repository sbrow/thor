package mustache

import "base:runtime"
import "core:strings"

// collect_struct_keys enumerates the visible field names of a struct value,
// including fields promoted via `using`-embedded structs.
collect_struct_keys :: proc(val: any, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, 0, 0, allocator)
	collect_struct_keys_into(val, &out, allocator)
	return out[:]
}

collect_struct_keys_into :: proc(val: any, out: ^[dynamic]string, allocator := context.allocator) {
	v, info := base_value(val)
	if info == nil {
		return
	}
	s, ok := info.variant.(runtime.Type_Info_Struct)
	if !ok {
		return
	}
	for i in 0 ..< int(s.field_count) {
		name := s.names[i]
		if len(name) == 0 {
			continue
		}
		if name[0] == '_' {
			continue
		}
		append(out, name)

		// Recurse into using-embedded struct fields to surface promoted names.
		if s.usings[i] {
			field_info := type_info_of(s.types[i].id)
			if field_info != nil {
				collect_struct_keys_into(any{v.data, s.types[i].id}, out, allocator)
			}
		}
	}
}

// struct_has_field reports whether a struct value has a named field,
// independent of whether that field's value is currently nil. This matters
// for fields like `Maybe(bool)` which can be nil but still exist.
struct_has_field :: proc(val: any, key: string) -> bool {
	v, info := base_value(val)
	if info == nil {
		return false
	}
	s, ok := info.variant.(runtime.Type_Info_Struct)
	if !ok {
		return false
	}
	for i in 0 ..< int(s.field_count) {
		if s.names[i] == key {
			return true
		}
		// Recurse into using-embedded fields.
		if s.usings[i] {
			if struct_has_field(any{v.data, s.types[i].id}, key) {
				return true
			}
		}
	}
	return false
}

// validate_key_path walks a dotted key path against the context stack and
// reports where (if anywhere) the lookup fails. Returns:
//   - ok: true if the entire path resolves, OR if the path crosses a map
//         (map keys are user-defined and not validated)
//   - missing_segment: the segment that failed (empty when ok)
//   - available: keys available at the failing level, for suggestions
validate_key_path :: proc(
	ctx: []any,
	key: string,
	allocator := context.temp_allocator,
) -> (
	ok: bool,
	missing_segment: string,
	available: []string,
) {
	parts: [16]string
	part_count := 0
	start := 0
	for i in 0 ..< len(key) {
		if key[i] == '.' {
			if part_count < len(parts) {
				parts[part_count] = key[start:i]
				part_count += 1
			}
			start = i + 1
		}
	}
	if part_count < len(parts) {
		parts[part_count] = key[start:]
		part_count += 1
	}
	if part_count == 0 {
		return true, "", nil
	}

	current: any = nil
	found := false
	for i := len(ctx) - 1; i >= 0; i -= 1 {
		current, found = lookup_in(ctx[i], parts[0])
		if found {
			break
		}
	}

	if !found {
		keys := make([dynamic]string, 0, 4, allocator)
		for i := len(ctx) - 1; i >= 0; i -= 1 {
			collect_struct_keys_into(ctx[i], &keys, allocator)
		}
		return false, parts[0], keys[:]
	}

	for i in 1 ..< part_count {
		v, info := base_value(current)
		if info == nil {
			return false, parts[i], nil
		}
		if _, is_map := info.variant.(runtime.Type_Info_Map); is_map {
			return true, "", nil
		}
		if _, is_struct := info.variant.(runtime.Type_Info_Struct); is_struct {
			if !struct_has_field(current, parts[i]) {
				return false, parts[i], collect_struct_keys(current, allocator)
			}
			// Field exists — descend into it. If the value is nil, stop here
			// (further segments can't be resolved but the current field is
			// legitimately present).
			next, found := lookup_in(current, parts[i])
			if !found {
				return true, "", nil
			}
			current = next
			continue
		}
		return false, parts[i], nil
	}

	return true, "", nil
}

// suggest_correction returns the closest match from `available` to `missing`
// using Levenshtein distance, or "" if no good match exists. The threshold
// scales with the length of the missing key.
suggest_correction :: proc(available: []string, missing: string) -> string {
	if len(available) == 0 || len(missing) == 0 {
		return ""
	}
	threshold := 2
	if len(missing) > 8 {
		threshold = len(missing) / 4
	}

	best: string
	best_dist := threshold + 1
	for candidate in available {
		if abs(len(candidate) - len(missing)) > threshold {
			continue
		}
		d := strings.levenshtein_distance(missing, candidate)
		if d <= threshold && d < best_dist {
			best = candidate
			best_dist = d
		}
	}
	return best
}

// collect_partial_names enumerates the keys of the partials map.
collect_partial_names :: proc(
	partials: map[string]Template,
	allocator := context.temp_allocator,
) -> []string {
	out := make([dynamic]string, 0, 0, allocator)
	for name in partials {
		append(&out, name)
	}
	return out[:]
}

// collect_block_names enumerates the unique `{{$name}}` block definitions in
// a template's node array.
collect_block_names :: proc(
	tmpl: Template,
	allocator := context.temp_allocator,
) -> []string {
	out := make([dynamic]string, 0, 0, allocator)
	seen := make(map[string]bool, allocator)
	defer delete(seen)
	for &node in tmpl.nodes {
		if node.kind == .Block {
			if !seen[node.key] {
				seen[node.key] = true
				append(&out, node.key)
			}
		}
	}
	return out[:]
}
