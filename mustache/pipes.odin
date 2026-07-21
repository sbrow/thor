package mustache

import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strings"
import "core:time"

// MAX_PIPES was chosen arbitrarily. It holds no performance or logical
// significance.
MAX_PIPES :: 8

// No filter accepts more than 2 args.
MAX_PIPE_ARGS :: 2

DEFAULT_DATE_FORMAT :: "2 Jan 2006"

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
	pos: int,
) -> (
	key: string,
	err: Error,
) {
	if !strings.contains(content, "|") {
		key = strings.trim_space(content)
		return key, nil
	}

	segments := strings.split(content, "|", allocator = context.temp_allocator)

	filter_count := len(segments) - 1
	if filter_count > MAX_PIPES {
		return "", Error_Body {
			msg = fmt.tprintf(
				"pipe expression has %d filters, max is %d",
				filter_count,
				MAX_PIPES,
			),
			pos = pos,
			kind = .Syntax,
		}
	}

	key = strings.trim_space(segments[0])
	if len(key) == 0 {
		return "", Error_Body{msg = "pipe expression missing key", pos = pos, kind = .Syntax}
	}

	if filter_count == 0 {
		return key, nil
	}

	for i in 0 ..< filter_count {
		seg := strings.trim_space(segments[i + 1])
		if len(seg) == 0 {
			return "", Error_Body{msg = "empty filter", pos = pos, kind = .Syntax}
		}

		tokens := strings.fields(seg)
		if len(tokens) == 0 {
			return "", Error_Body{msg = "filter missing op name", pos = pos, kind = .Syntax}
		}

		arg_count := len(tokens) - 1
		if arg_count > MAX_PIPE_ARGS {
			return "", Error_Body {
				msg = fmt.tprintf(
					"filter '%s' has %d args, max is %d",
					tokens[0],
					arg_count,
					MAX_PIPE_ARGS,
				),
				pos = pos,
				kind = .Syntax,
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

apply_pipeline :: proc(
	value: any,
	filters: []Pipe_Filter,
	pos: int,
	ctx: []any,
) -> (
	current: any,
	err: Error,
) {
	current = value
	for &filter in filters {
		current = apply_filter(current, &filter, pos, ctx) or_return
		log.debugf("applied: filter=%v before=%s after=%s pos=%d", filter, value, current, pos)
	}
	return
}

// TODO: diagnostics don't  show anything relevent
apply_filter :: proc(value: any, filter: ^Pipe_Filter, pos: int, ctx: []any) -> (any, Error) {
	switch filter.op {
	case "group_by":
		return apply_group_by(value, filter.args[:], pos)
	case "format":
		str, ok := reflect.as_string(value)
		if !ok {
			return value, Error_Body {
				msg = "format may only be used on dates",
				pos = pos,
				kind = .Data,
			}
		}

		date_format: string

		if len(filter.args) > 0 {
			date_format = filter.args[0]
		} else {
			date_format_raw := resolve_name("date_format", ctx)
			if date_format_raw == nil {
				return value, Error_Body {
					msg = "Unable to determine date format",
					pos = pos,
					kind = .Data,
				}
			} else {
				valid: bool
				date_format, valid = reflect.as_string(date_format_raw)
				if !valid {
					return value, Error_Body {
						msg = "date format is not a string",
						pos = pos,
						kind = .Data,
					}
				}
			}
		}

		str2, err := apply_format(str, filter.args[:], pos, date_format)
		if err != nil {
			return value, err
		} else {
			return any{new_clone(str2, context.temp_allocator), typeid_of(string)}, nil
		}

	case:
		return nil, Error_Body {
			msg = fmt.tprintf("unknown pipe op '%s'", filter.op),
			pos = pos,
			kind = .Data,
		}
	}
}

apply_format :: proc(
	iso: string,
	args: []string,
	pos: int,
	date_format: string,
) -> (
	result: string,
	err: Error,
) {
	fmt_str := date_format
	if fmt_str == "" {
		log.errorf(
			"format pipe used but no date format configured (set date.format in thor.json) Default will be used",
		)
		fmt_str = DEFAULT_DATE_FORMAT
	}

	components, ok := parse_iso_date(iso)
	if !ok {
		return "", Error_Body {
			msg = fmt.tprintf("invalid date: \"%s\"", iso),
			pos = pos,
			kind = .Data,
		}
	}

	log.debugf("date: '%s' format: '%s'", iso, date_format)
	return format_date(components, fmt_str), nil
}

// Groups preserve first-appearance order from the input list.
apply_group_by :: proc(value: any, args: []string, pos: int) -> (result: any, err: Error) {
	if len(args) != 1 {
		return nil, Error_Body {
			msg = fmt.tprintf("group_by expects 1 argument, got %d", len(args)),
			pos = pos,
			kind = .Data,
		}
	}
	field := args[0]

	elem_info, count, data := list_info(value)
	if elem_info == nil {
		return nil, Error_Body{msg = "group_by expects a list", pos = pos, kind = .Data}
	}

	groups := make([dynamic]Group, 0, 8, context.temp_allocator)
	key_to_idx := make(map[string]int, context.temp_allocator)
	defer delete(key_to_idx)

	for j in 0 ..< count {
		elem_ptr := rawptr(uintptr(data) + uintptr(j) * uintptr(elem_info.size))
		elem := any{elem_ptr, elem_info.id}

		key_val, found := lookup_in(elem, field)
		if !found {
			return nil, Error_Body {
				msg = fmt.tprintf("group_by: element missing field '%s'", field),
				pos = pos,
				kind = .Data,
			}
		}
		key_str := any_to_string(key_val)
		if len(key_str) == 0 {
			return nil, Error_Body {
				msg = fmt.tprintf("group_by: field '%s' is empty", field),
				pos = pos,
				kind = .Data,
			}
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

