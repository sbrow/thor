package mustache

import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:time"

// MAX_PIPES was chosen arbitrarily. It holds no performance or logical
// significance.
MAX_PIPES :: 8

// No filter accepts more than 2 args.
MAX_PIPE_ARGS :: 2

Pipe_Filter :: struct {
	op:   string,
	args: [dynamic; MAX_PIPE_ARGS]string,
}

Group :: struct {
	key:   string,
	items: [dynamic]any,
}

// Returned strings are slices into content — no cloning, lifetime bound to
// the caller's source.
parse_pipeline :: proc(
	content: string,
	filters_out: ^[dynamic; MAX_PIPES]Pipe_Filter,
) -> (
	key: string,
	err: Render_Error,
) {
	if !strings.contains(content, "|") {
		key = strings.trim_space(content)
		return key, nil
	}

	segments := strings.split(content, "|", allocator = context.temp_allocator)

	filter_count := len(segments) - 1
	if filter_count > MAX_PIPES {
		return "", Syntax_Error {
			msg = fmt.tprintf(
				"pipe expression has %d filters, max is %d",
				filter_count,
				MAX_PIPES,
			),
		}
	}

	key = strings.trim_space(segments[0])
	if len(key) == 0 {
		return "", Syntax_Error{msg = "pipe expression missing key"}
	}

	if filter_count == 0 {
		return key, nil
	}

	for i in 0 ..< filter_count {
		seg := strings.trim_space(segments[i + 1])
		if len(seg) == 0 {
			return "", Syntax_Error{msg = "empty filter"}
		}

		tokens := strings.fields(seg)
		if len(tokens) == 0 {
			return "", Syntax_Error{msg = "filter missing op name"}
		}

		arg_count := len(tokens) - 1
		if arg_count > MAX_PIPE_ARGS {
			return "", Syntax_Error {
				msg = fmt.tprintf(
					"filter '%s' has %d args, max is %d",
					tokens[0],
					arg_count,
					MAX_PIPE_ARGS,
				),
			}
		}

		filter := Pipe_Filter {
			op = tokens[0],
		}
		for j in 1 ..< len(tokens) {
			append(&filter.args, tokens[j])
		}
		append(filters_out, filter)
		delete(tokens)
	}

	return key, nil
}

apply_pipeline :: proc(value: any, filters: []Pipe_Filter) -> (any, Render_Error) {
	current := value
	for &filter in filters {
		result, err := apply_filter(current, &filter)
		if err != nil {
			return nil, err
		}
		current = result
	}
	return current, nil
}

apply_filter :: proc(value: any, filter: ^Pipe_Filter) -> (any, Render_Error) {
	switch filter.op {
	case "group_by":
		return apply_group_by(value, filter.args[:])
	case "format":
		str, ok := reflect.as_string(value)
		if !ok {
			return value, Data_Error{msg = "format may only be used on dates"}
		} else {
			return apply_format(str, filter.args[:])
		}
	case:
		return nil, Data_Error{msg = fmt.tprintf("unknown pipe op '%s'", filter.op)}
	}
}

// apply_format formats an ISO 8601 date string as a display string
// (e.g. "2026-03-15T08:49:54-04:00" → "15 Mar 2026"). Invalid input
// (empty, too-short, or unparseable) returns a `Data_Error`. Templates
// that need to skip dateless pages should gate with a section:
//   {{#date}}<time datetime="{{.}}">{{. | format}}</time>{{/date}}
// The section's truthiness check catches empty before the filter runs.
//
// Currently ignores args; planned to accept Go reference-date format
// strings in the future.
//
// Accepts any of these ISO 8601 forms (date prefix is invariant):
//   2023-10-15T13:18:50-07:00
//   2023-10-15T13:18:50-0700
//   2023-10-15T13:18:50Z
//   2023-10-15T13:18:50
//   2023-10-15
apply_format :: proc(iso: string, args: []string) -> (result: any, err: Render_Error) {
	if len(iso) < 10 {
		return nil, Data_Error{msg = "format may only be used on dates"}
	}

	year := iso[:4]
	month_num := (int(iso[5]) - 0x30) * 10 + (int(iso[6]) - 0x30)
	day_num := (int(iso[8]) - 0x30) * 10 + (int(iso[9]) - 0x30)

	if month_num < 1 || month_num > 12 {
		return nil, Data_Error{msg = fmt.tprintf("invalid date: \"%s\"", iso)}
	}

	month := fmt.tprintf("%s", time.Month(month_num))[:3]
	return fmt.tprintf("%d %s %s", day_num, month, year), nil
}

// Groups preserve first-appearance order from the input list.
apply_group_by :: proc(value: any, args: []string) -> (result: any, err: Render_Error) {
	if len(args) != 1 {
		return nil, Data_Error{msg = fmt.tprintf("group_by expects 1 argument, got %d", len(args))}
	}
	field := args[0]

	elem_info, count, data := list_info(value)
	if elem_info == nil {
		return nil, Data_Error{msg = "group_by expects a list"}
	}

	groups := make([dynamic]Group, 0, 8, context.temp_allocator)
	key_to_idx := make(map[string]int, context.temp_allocator)
	defer delete(key_to_idx)

	for j in 0 ..< count {
		elem_ptr := rawptr(uintptr(data) + uintptr(j) * uintptr(elem_info.size))
		elem := any{elem_ptr, elem_info.id}

		key_val, found := lookup_in(elem, field)
		if !found {
			return nil, Data_Error {
				msg = fmt.tprintf("group_by: element missing field '%s'", field),
			}
		}
		key_str := any_to_string(key_val)
		if len(key_str) == 0 {
			return nil, Data_Error{msg = fmt.tprintf("group_by: field '%s' is empty", field)}
		}

		idx, exists := key_to_idx[key_str]
		if !exists {
			idx = len(groups)
			key_to_idx[key_str] = idx
			append(
				&groups,
				Group{key = key_str, items = make([dynamic]any, 0, 4, context.temp_allocator)},
			)
		}
		append(&groups[idx].items, elem)
	}

	return groups, nil
}

