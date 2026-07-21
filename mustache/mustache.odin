package mustache

import "core:fmt"
import "core:log"
import "core:strings"

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

Error_Kind :: enum {
	Syntax, // parse-time: malformed template
	Data,   // render-time: template fine, data wrong (e.g. filter misuse)
}

Error_Body :: struct {
	msg:  string,
	pos:  int,
	kind: Error_Kind,
}

// Error is nil when no error occurred.
Error :: union { Error_Body }

// body unwraps the Error_Body from a non-nil Error.
// Precondition: err != nil.
body :: proc(err: Error) -> Error_Body {
	switch e in err {
	case Error_Body: return e
	case: return {}
	}
}

// ---------------------------------------------------------------------------
// Node tree
// ---------------------------------------------------------------------------

Node_Kind :: enum {
	Text,
	Variable,
	Unescaped,
	Section,
	Inverted,
	Partial,
	Parent,
	Block,
}

Node :: struct {
	kind:        Node_Kind,
	text:        string,
	key:         string,
	filters:     [dynamic; MAX_PIPES]Pipe_Filter,
	is_dynamic:  bool,
	indent:      string,
	first_child: int,
	child_count: int,
	content:     string,
	pos:         int,
}

// node_span returns the number of flat-array entries a node occupies:
// 1 for leaf nodes, 1 + child_count for container nodes (whose children
// are stored contiguously after them in the array).
node_span :: proc(n: Node) -> int {
	#partial switch n.kind {
	case .Section, .Inverted, .Parent, .Block:
		return 1 + n.child_count
	case:
		return 1
	}
}

Template :: struct {
	nodes:  [dynamic]Node,
	source: string,
	path:   string,
}

Block_Override :: struct {
	all_nodes: []Node,
	first:     int,
	count:     int,
	source:    Template,
}

delete_template :: proc(tmpl: ^Template) {
	if tmpl != nil && len(tmpl.nodes) > 0 {
		delete(tmpl.nodes)
	}
}

delete_partials :: proc(partials: map[string]Template) {
	for _, &p in partials {
		delete_template(&p)
	}
	delete(partials)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

parse :: proc(
	source: string,
	path := "",
	allocator := context.allocator,
	tokens_allocator := context.temp_allocator,
) -> (
	tmpl: Template,
	err: Error,
) {
	tokens, terr := tokenize(source, tokens_allocator)
	if terr != nil {
		return {}, terr
	}

	tmpl.nodes, err = parse_tokens(tokens[:], source, allocator)
	if err != nil {
		delete(tmpl.nodes)
		return {}, err
	}
	tmpl.source = source
	tmpl.path = path
	deindent_blocks(tmpl.nodes[:], 0, len(tmpl.nodes), allocator)
	return tmpl, nil
}

render :: proc(
	tmpl: Template,
	data: any,
	partials: map[string]Template = nil,
	allocator := context.allocator,
) -> (
	result: string,
	err: Error,
) {
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	defer strings.builder_destroy(&builder)

	ctx := make([dynamic]any, 0, 4, allocator)
	defer delete(ctx)
	append(&ctx, data)

	all_nodes := tmpl.nodes[:]
	err = render_nodes(tmpl, all_nodes, all_nodes, &ctx, partials, &builder)
	if err != nil {
		return result, err
	}

	temp := strings.to_string(builder)
	result = strings.clone(temp, allocator)

	return result, err
}

// ---------------------------------------------------------------------------
// Parser — flat token list → flat node array with child indices
// ---------------------------------------------------------------------------

parse_tokens :: proc(
	tokens: []Token,
	source: string,
	allocator := context.allocator,
) -> (
	nodes: [dynamic]Node,
	err: Error,
) {
	nodes = make([dynamic]Node, 0, len(tokens), allocator)
	pos := 0
	err = parse_section(tokens, &pos, &nodes, "", source, allocator, 0)
	return
}

parse_section :: proc(
	tokens: []Token,
	pos: ^int,
	nodes: ^[dynamic]Node,
	end_tag: string,
	source: string,
	allocator := context.allocator,
	open_pos: int = 0,
) -> Error {
	for pos^ < len(tokens) {
		tok := tokens[pos^]

		switch tok.kind {
		case .Text:
			append(nodes, Node{kind = .Text, text = tok.value, first_child = -1, pos = tok.pos})
			pos^ += 1

		case .Variable:
			idx := len(nodes)
			append(nodes, Node{kind = .Variable, first_child = -1})
			pipe_key, perr := parse_pipeline(tok.value, &nodes[idx].filters, tok.pos)
			if perr != nil {
				return Error_Body {
					msg = fmt.tprintf("pipe parse error in '{{{{%s}}}}': %v", tok.value, perr),
					pos = tok.pos,
					kind = .Syntax,
				}
			}
			nodes[idx].key = pipe_key
			pos^ += 1

		case .Unescaped:
			idx := len(nodes)
			append(nodes, Node{kind = .Unescaped, first_child = -1})
			pipe_key, perr := parse_pipeline(tok.value, &nodes[idx].filters, tok.pos)
			if perr != nil {
				return Error_Body {
					msg = fmt.tprintf("pipe parse error in '{{{{&%s}}}}': %v", tok.value, perr),
					pos = tok.pos,
					kind = .Syntax,
				}
			}
			nodes[idx].key = pipe_key
			pos^ += 1

		case .Comment:
			pos^ += 1

		case .Section_Open:
			pos^ += 1
			idx := len(nodes)
			content_start := 0
			if pos^ < len(tokens) {content_start = tokens[pos^].pos}
			append(nodes, Node{kind = .Section, first_child = -1, pos = tok.pos})
			pipe_key, perr := parse_pipeline(tok.value, &nodes[idx].filters, tok.pos)
			if perr != nil {
				return Error_Body {
					msg = fmt.tprintf("pipe parse error in '{{{{#%s}}}}': %v", tok.value, perr),
					pos = tok.pos,
					kind = .Syntax,
				}
			}
			nodes[idx].key = pipe_key
			parse_section(tokens, pos, nodes, pipe_key, source, allocator, tok.pos) or_return
			close_pos := 0
			if pos^ - 1 >= 0 && pos^ - 1 < len(tokens) {close_pos = tokens[pos^ - 1].pos}
			nodes[idx].first_child = idx + 1
			nodes[idx].child_count = len(nodes) - idx - 1
			nodes[idx].content = source[content_start:close_pos]

		case .Inverted_Open:
			pos^ += 1
			idx := len(nodes)
			content_start := 0
			if pos^ < len(tokens) {content_start = tokens[pos^].pos}
			append(nodes, Node{kind = .Inverted, first_child = -1, pos = tok.pos})
			pipe_key, perr := parse_pipeline(tok.value, &nodes[idx].filters, tok.pos)
			if perr != nil {
				return Error_Body {
					msg = fmt.tprintf("pipe parse error in '{{{{^%s}}}}': %v", tok.value, perr),
					pos = tok.pos,
					kind = .Syntax,
				}
			}
			nodes[idx].key = pipe_key
			parse_section(tokens, pos, nodes, pipe_key, source, allocator, tok.pos) or_return
			close_pos := 0
			if pos^ - 1 >= 0 && pos^ - 1 < len(tokens) {close_pos = tokens[pos^ - 1].pos}
			nodes[idx].first_child = idx + 1
			nodes[idx].child_count = len(nodes) - idx - 1
			nodes[idx].content = source[content_start:close_pos]

		case .Section_Close:
			if strings.contains(tok.value, "|") {
			return Error_Body {
				msg = fmt.tprintf(
					"pipe expression not allowed in close tag '{{{{/%s}}}}' — use the bare key",
					tok.value,
				),
				pos = tok.pos,
				kind = .Syntax,
			}
			}
			if end_tag != "" && tok.value == end_tag {
				pos^ += 1
				return nil
			}
			if end_tag == "" {
				return Error_Body {
					msg = fmt.tprintf("unexpected {{{{/%s}}}}", tok.value),
					pos = tok.pos,
					kind = .Syntax,
				}
			}
			return Error_Body {
				msg = fmt.tprintf("expected {{{{/%s}}}}, got {{{{/%s}}}}", end_tag, tok.value),
				pos = tok.pos,
				kind = .Syntax,
			}

		case .Partial:
			append(
				nodes,
				Node {
					kind = .Partial,
					key = tok.value,
					is_dynamic = tok.is_dynamic,
					indent = tok.indent,
					first_child = -1,
					pos = tok.pos,
				},
			)
			pos^ += 1

		case .Parent:
			pos^ += 1
			idx := len(nodes)
			append(
				nodes,
				Node {
					kind = .Parent,
					key = tok.value,
					indent = tok.indent,
					first_child = -1,
					pos = tok.pos,
				},
			)
			parse_section(tokens, pos, nodes, tok.value, source, allocator, tok.pos) or_return
			nodes[idx].first_child = idx + 1
			nodes[idx].child_count = len(nodes) - idx - 1

		case .Block_Open:
			pos^ += 1
			idx := len(nodes)
			append(
				nodes,
				Node {
					kind = .Block,
					key = tok.value,
					indent = tok.indent,
					first_child = -1,
					pos = tok.pos,
				},
			)
			parse_section(tokens, pos, nodes, tok.value, source, allocator, tok.pos) or_return
			nodes[idx].first_child = idx + 1
			nodes[idx].child_count = len(nodes) - idx - 1
		}
	}

	if end_tag != "" {
		return Error_Body {
			msg = fmt.tprintf("unclosed section '{{{{#%s}}}}'", end_tag),
			pos = open_pos,
			kind = .Syntax,
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Post-parse: de-indent block content
// ---------------------------------------------------------------------------

deindent_blocks :: proc(all_nodes: []Node, start: int, end: int, allocator := context.allocator) {
	i := start
	for i < end {
		#partial switch all_nodes[i].kind {
		case .Block:
			if all_nodes[i].child_count > 0 {
				cs := all_nodes[i].first_child
				ce := cs + all_nodes[i].child_count
				deindent_blocks(all_nodes, cs, ce, allocator)

				children := all_nodes[cs:ce]
				common := find_common_indent(children)
				if len(common) > 0 {
					if len(all_nodes[i].indent) == 0 {
						all_nodes[i].indent = common
					}
					for j := cs; j < ce; {
						if all_nodes[j].kind == .Text && len(all_nodes[j].text) > 0 {
							all_nodes[j].text = remove_line_indent(
								all_nodes[j].text,
								common,
								allocator,
							)
						}
						j += node_span(all_nodes[j])
					}
				}
			}

		case .Section, .Inverted, .Parent:
			if all_nodes[i].child_count > 0 {
				cs := all_nodes[i].first_child
				ce := cs + all_nodes[i].child_count
				deindent_blocks(all_nodes, cs, ce, allocator)
			}
		}
		i += node_span(all_nodes[i])
	}
}

find_common_indent :: proc(children: []Node) -> string {
	common: string
	found := false

	i := 0
	for i < len(children) {
		if children[i].kind == .Text {
			text := children[i].text
			if len(text) > 0 {
				line_start := 0
				for j in 0 ..= len(text) {
					if j == len(text) || text[j] == '\n' {
						line := text[line_start:j]
						if len(strings.trim_space(line)) > 0 {
							ws := leading_whitespace(line)
							if !found {
								common = ws
								found = true
							} else if len(ws) < len(common) {
								common = ws
							}
						}
						line_start = j + 1
					}
				}
			}
		}
		i += node_span(children[i])
	}

	if found {
		return common
	} else {
		return ""
	}
}

leading_whitespace :: proc(s: string) -> string {
	for i in 0 ..< len(s) {
		if s[i] != ' ' && s[i] != '\t' {
			return s[:i]
		}
	}
	return s
}

remove_line_indent :: proc(s: string, indent: string, allocator := context.allocator) -> string {
	if len(indent) == 0 {
		return s
	}

	buf := make([dynamic]u8, 0, len(s), allocator)
	i := 0
	at_line_start := true

	for i < len(s) {
		if at_line_start {
			if i + len(indent) <= len(s) && s[i:i + len(indent)] == indent {
				i += len(indent)
				at_line_start = false
				continue
			}
			at_line_start = false
		}
		append(&buf, s[i])
		if s[i] == '\n' {
			at_line_start = true
		}
		i += 1
	}

	return string(buf[:])
}

// ---------------------------------------------------------------------------
// Indentation helpers
// ---------------------------------------------------------------------------

indent_lines :: proc(source: string, indent: string) -> string {
	if len(indent) == 0 || len(source) == 0 {
		return source
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	write_indented(&b, indent, source)
	return strings.to_string(b)
}

write_indented :: proc(b: ^strings.Builder, indent: string, content: string) {
	if len(indent) == 0 || len(content) == 0 {
		strings.write_string(b, content)
		return
	}
	at_line_start := true
	for i in 0 ..< len(content) {
		if at_line_start {
			strings.write_string(b, indent)
			at_line_start = false
		}
		strings.write_byte(b, content[i])
		if content[i] == '\n' {
			at_line_start = true
		}
	}
}

render_template :: proc(
	pt: Template,
	ctx: ^[dynamic]any,
	partials: map[string]Template,
	b: ^strings.Builder,
	blocks: map[string]Block_Override,
	indent: string,
) -> Error {
	if len(indent) > 0 && len(pt.source) > 0 {
		// Per Mustache spec: the partial's source is indented before rendering,
		// not its output. This is necessary so that data-injected newlines
		// (e.g. from `{{{content}}}` where content contains `\n`) do NOT pick
		// up the indent — only source-level line breaks do.
		indented := indent_lines(pt.source, indent)
		reparse := parse(
			indented,
			pt.path,
			context.temp_allocator,
			context.temp_allocator,
		) or_return
		return render_nodes(reparse, reparse.nodes[:], reparse.nodes[:], ctx, partials, b, blocks)
	}
	return render_nodes(pt, pt.nodes[:], pt.nodes[:], ctx, partials, b, blocks)
}

// ---------------------------------------------------------------------------
// Renderer — walk node array against context stack, write to builder
// ---------------------------------------------------------------------------

render_nodes :: proc(
	current: Template,
	all_nodes: []Node,
	nodes: []Node,
	ctx: ^[dynamic]any,
	partials: map[string]Template,
	b: ^strings.Builder,
	blocks: map[string]Block_Override = nil,
) -> Error {
	i := 0
	for i < len(nodes) {
		node := nodes[i]
		switch node.kind {
		case .Text:
			strings.write_string(b, node.text)
			i += 1

		case .Variable:
			val := resolve_name(node.key, ctx[:])
			if val == nil {
				warn_unknown_key(current, ctx[:], node)
			}
			if len(node.filters) > 0 {
				transformed, perr := apply_pipeline(val, node.filters[:], node.pos)
				if perr != nil {
					return perr
				}
				val = transformed
			}
			if result_str, ok := call_interp_lambda(val); ok {
				sub_tpl, perr := parse(
					result_str,
					fmt.tprintf("<lambda output from '%s'>", node.key),
					context.temp_allocator,
					context.temp_allocator,
				)
				if perr == nil {
					temp: strings.Builder
					strings.builder_init(&temp, context.temp_allocator)
					render_nodes(
						sub_tpl,
						sub_tpl.nodes[:],
						sub_tpl.nodes[:],
						ctx,
						partials,
						&temp,
						blocks,
					) or_return
					write_value(b, strings.to_string(temp), escape = true)
				}
			} else {
				write_value(b, val, escape = true)
			}
			i += 1

		case .Unescaped:
			val := resolve_name(node.key, ctx[:])
			if val == nil {
				warn_unknown_key(current, ctx[:], node)
			}
			if len(node.filters) > 0 {
				transformed, perr := apply_pipeline(val, node.filters[:], node.pos)
				if perr != nil {
					return perr
				}
				val = transformed
			}
			if result_str, ok := call_interp_lambda(val); ok {
				sub_tpl, perr := parse(
					result_str,
					fmt.tprintf("<lambda output from '%s'>", node.key),
					context.temp_allocator,
					context.temp_allocator,
				)
				if perr == nil {
					temp: strings.Builder
					strings.builder_init(&temp, context.temp_allocator)
					render_nodes(
						sub_tpl,
						sub_tpl.nodes[:],
						sub_tpl.nodes[:],
						ctx,
						partials,
						&temp,
						blocks,
					) or_return
					write_value(b, strings.to_string(temp), escape = false)
				}
			} else {
				write_value(b, val, escape = false)
			}
			i += 1

		case .Section:
			val := resolve_name(node.key, ctx[:])
			if val == nil {
				warn_unknown_key(current, ctx[:], node)
			}
			if len(node.filters) > 0 {
				transformed, perr := apply_pipeline(val, node.filters[:], node.pos)
				if perr != nil {
					return perr
				}
				val = transformed
			}
			if result_str, ok := call_section_lambda(val, node.content); ok {
				sub_tpl, perr := parse(
					result_str,
					fmt.tprintf("<lambda output from '%s'>", node.key),
					context.temp_allocator,
					context.temp_allocator,
				)
				if perr == nil {
					render_nodes(
						sub_tpl,
						sub_tpl.nodes[:],
						sub_tpl.nodes[:],
						ctx,
						partials,
						b,
						blocks,
					) or_return
				}
			} else if is_truthy(val) {
				children := all_nodes[node.first_child:node.first_child + node.child_count]
				elem_info, count, data := list_info(val)
				if elem_info != nil {
					for j in 0 ..< count {
						elem := extract_list_element(elem_info, data, j)
						append(ctx, elem)
						defer pop(ctx)
						render_nodes(
							current,
							all_nodes,
							children,
							ctx,
							partials,
							b,
							blocks,
						) or_return
					}
				} else {
					append(ctx, val)
					defer pop(ctx)
					render_nodes(current, all_nodes, children, ctx, partials, b, blocks) or_return
				}
			}
			i += 1 + node.child_count

		case .Inverted:
			val := resolve_name(node.key, ctx[:])
			if val == nil {
				warn_unknown_key(current, ctx[:], node)
			}
			if len(node.filters) > 0 {
				transformed, perr := apply_pipeline(val, node.filters[:], node.pos)
				if perr != nil {
					return perr
				}
				val = transformed
			}
			if !is_truthy(val) {
				children := all_nodes[node.first_child:node.first_child + node.child_count]
				render_nodes(current, all_nodes, children, ctx, partials, b, blocks) or_return
			}
			i += 1 + node.child_count

		case .Partial:
			name := node.key
			if node.is_dynamic {
				val := resolve_name(node.key, ctx[:])
				name = any_to_string(val)
			}
			pt, found := partials[name]
			if !found {
				warn_missing_partial(current, partials, node, name)
			} else {
				render_template(pt, ctx, partials, b, nil, node.indent) or_return
			}
			i += 1

		case .Block:
			content_nodes: []Node
			content_pool: []Node
			content_blocks := blocks
			render_current := current

			found_override := false
			if blocks != nil {
				if o, ok := blocks[node.key]; ok {
					content_nodes = o.all_nodes[o.first:o.first + o.count]
					content_pool = o.all_nodes
					found_override = true
					render_current = o.source
				}
			}
			if !found_override {
				content_nodes = all_nodes[node.first_child:node.first_child + node.child_count]
				content_pool = all_nodes
			}

			if len(node.indent) > 0 {
				temp: strings.Builder
				strings.builder_init(&temp, context.temp_allocator)
				render_nodes(
					render_current,
					content_pool,
					content_nodes,
					ctx,
					partials,
					&temp,
					content_blocks,
				) or_return
				write_indented(b, node.indent, strings.to_string(temp))
			} else {
				render_nodes(
					render_current,
					content_pool,
					content_nodes,
					ctx,
					partials,
					b,
					content_blocks,
				) or_return
			}
			i += 1 + node.child_count

		case .Parent:
			parent_children := all_nodes[node.first_child:node.first_child + node.child_count]
			merged := merge_block_overrides(parent_children, all_nodes, blocks, current)
			pt, found := partials[node.key]
			if !found {
				warn_missing_partial(current, partials, node, node.key)
			} else {
				warn_unmatched_block_overrides(current, pt, parent_children)
				render_template(pt, ctx, partials, b, merged, node.indent) or_return
			}
			i += 1 + node.child_count
		}
	}
	return nil
}

merge_block_overrides :: proc(
	children: []Node,
	all_nodes: []Node,
	existing: map[string]Block_Override,
	source: Template,
) -> map[string]Block_Override {
	result := make(map[string]Block_Override, context.temp_allocator)

	for name, override in existing {
		result[name] = override
	}

	i := 0
	for i < len(children) {
		child := children[i]
		if child.kind == .Block {
			if _, exists := result[child.key]; !exists {
				result[child.key] = Block_Override {
					all_nodes = all_nodes,
					first     = child.first_child,
					count     = child.child_count,
					source    = source,
				}
			}
		}
		i += node_span(child)
	}

	return result
}

// warn_unknown_key checks whether the missing key is a genuine typo (vs. a
// legitimate path through a user-defined map) and, if so, emits a diagnostic
// warning with the closest field-name suggestion via Levenshtein.
warn_unknown_key :: proc(current: Template, ctx: []any, node: Node) {
	// `{{.}}` and dot-prefixed names refer to the current context — always valid.
	if node.key == "." || (len(node.key) > 0 && node.key[0] == '.') {
		return
	}

	path_ok, missing, available := validate_key_path(ctx, node.key)
	if path_ok {
		return
	}

	hint := ""
	if len(available) > 0 {
		suggestion := suggest_correction(available, missing)
		if suggestion != "" {
			hint = fmt.tprintf("did you mean '%s'?", suggestion)
		}
	}
	msg := fmt.tprintf("unknown key '%s'", node.key)
	path := current.path
	if path == "" {
		path = "<input>"
	}
	diag := format_error(path, current.source, node.pos, msg, hint, colorize = should_colorize())
	log.warnf("%s", diag)
}

// warn_missing_partial emits a warning when a `{{> name}}` or `{{<name}}` tag
// references a partial that isn't in the partials map.
warn_missing_partial :: proc(
	current: Template,
	partials: map[string]Template,
	node: Node,
	name: string,
) {
	hint := ""
	available := collect_partial_names(partials)
	suggestion := suggest_correction(available, name)
	if suggestion != "" {
		hint = fmt.tprintf("did you mean '%s'?", suggestion)
	}
	msg := fmt.tprintf("partial '%s' not found", name)
	path := current.path
	if path == "" {
		path = "<input>"
	}
	diag := format_error(path, current.source, node.pos, msg, hint, colorize = should_colorize())
	log.warnf("%s", diag)
}

// warn_unmatched_block_overrides checks each `{{$name}}...{{/name}}` block
// defined inside a `{{<parent}}` tag and warns when the name doesn't match
// any block in the parent template.
warn_unmatched_block_overrides :: proc(
	current: Template,
	parent: Template,
	parent_children: []Node,
) {
	if len(parent_children) == 0 {
		return
	}
	available := collect_block_names(parent)
	parent_path := parent.path
	if parent_path == "" {
		parent_path = "<input>"
	}
	for child in parent_children {
		if child.kind != .Block {
			continue
		}
		matched := false
		for name in available {
			if name == child.key {
				matched = true
				break
			}
		}
		if matched {
			continue
		}

		hint := ""
		suggestion := suggest_correction(available, child.key)
		if suggestion != "" {
			hint = fmt.tprintf("did you mean '%s'?", suggestion)
		}
		msg := fmt.tprintf(
			"block override '%s' has no match in parent template '%s'",
			child.key,
			parent_path,
		)
		path := current.path
		if path == "" {
			path = "<input>"
		}
		diag := format_error(
			path,
			current.source,
			child.pos,
			msg,
			hint,
			colorize = should_colorize(),
		)
		log.warnf("%s", diag)
	}
}

