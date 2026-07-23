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

// is_pipe_space reports whether c is whitespace for the purposes of
// tokenizing a filter segment.
is_pipe_space :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

// tokenize_fields splits seg on whitespace like strings.fields, but a
// double-quoted span (spaces allowed inside) becomes a single token. The
// quote characters are kept in the token (not stripped) so callers can
// distinguish a quoted literal from a bare key name. No escape sequences.
tokenize_fields :: proc(seg: string, pos: int) -> (tokens: [dynamic]string, err: Error) {
	i := 0
	for i < len(seg) {
		for i < len(seg) && is_pipe_space(seg[i]) {
			i += 1
		}
		if i >= len(seg) {
			break
		}
		if seg[i] == '"' {
			start := i
			j := i + 1
			for j < len(seg) && seg[j] != '"' {
				j += 1
			}
			if j >= len(seg) {
				return tokens, Error_Body {
					msg  = fmt.tprintf("unterminated string literal: %s", seg),
					pos  = pos,
					kind = .Syntax,
				}
			}
			append(&tokens, seg[start:j + 1])
			i = j + 1
		} else {
			start := i
			for i < len(seg) && !is_pipe_space(seg[i]) {
				i += 1
			}
			append(&tokens, seg[start:i])
		}
	}
	return tokens, nil
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

		tokens, terr := tokenize_fields(seg, pos)
		if terr != nil {
			delete(tokens)
			return "", terr
		}
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

// resolve_format_string looks up name as a context key and returns its
// string value. Used both for an explicit bare-key filter arg (e.g.
// `format long`) and for the implicit "date_format" fallback when no arg
// is given.
resolve_format_string :: proc(name: string, ctx: []any, pos: int) -> (string, Error) {
	raw := resolve_name(name, ctx)
	if raw == nil {
		return "", Error_Body {
			msg  = fmt.tprintf("unable to resolve date format key '%s'", name),
			pos  = pos,
			kind = .Data,
		}
	}
	str, ok := reflect.as_string(raw)
	if !ok {
		return "", Error_Body {
			msg  = fmt.tprintf("date format key '%s' is not a string", name),
			pos  = pos,
			kind = .Data,
		}
	}
	return str, nil
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
			arg := filter.args[0]
			if len(arg) >= 2 && arg[0] == '"' && arg[len(arg) - 1] == '"' {
				date_format = arg[1:len(arg) - 1]
			} else {
				df, ferr := resolve_format_string(arg, ctx, pos)
				if ferr != nil {
					return value, ferr
				}
				date_format = df
			}
		} else {
			df, ferr := resolve_format_string("date_format", ctx, pos)
			if ferr != nil {
				return value, ferr
			}
			date_format = df
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

