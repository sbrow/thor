package mustache

import "core:fmt"
import "core:strings"

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

Syntax_Error :: struct {
	msg: string,
	pos: int,
}
Data_Error :: struct {
	msg: string,
}
Partial_Error :: struct {
	name: string,
	msg:  string,
}

Render_Error :: union {
	Syntax_Error,
	Data_Error,
	Partial_Error,
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
	is_dynamic:  bool,
	indent:      string,
	first_child: int,
	child_count: int,
}

Template :: struct {
	nodes: [dynamic]Node,
}

Block_Override :: struct {
	all_nodes: []Node,
	first:     int,
	count:     int,
}

template_free :: proc(tmpl: ^Template) {
	if tmpl != nil && len(tmpl.nodes) > 0 {
		delete(tmpl.nodes)
	}
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

parse :: proc(
	source: string,
	allocator := context.allocator,
	tokens_allocator := context.temp_allocator,
) -> (
	tmpl: Template,
	err: Render_Error,
) {
	tokens, terr := tokenize(source, tokens_allocator)
	if terr != nil {
		return {}, terr
	}

	tmpl.nodes, err = parse_tokens(tokens[:], allocator)
	if err != nil {
		delete(tmpl.nodes)
	}
	return tmpl, err
}

render :: proc(
	tmpl: Template,
	data: any,
	partials: map[string]Template = nil,
	allocator := context.allocator,
) -> (
	result: string,
	err: Render_Error,
) {
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	defer strings.builder_destroy(&builder)

	ctx := make([dynamic]any, 0, 4, allocator)
	defer delete(ctx)
	append(&ctx, data)

	all_nodes := tmpl.nodes[:]
	err = render_nodes(all_nodes, all_nodes, &ctx, partials, &builder)
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
	allocator := context.allocator,
) -> (
	nodes: [dynamic]Node,
	err: Render_Error,
) {
	nodes = make([dynamic]Node, 0, len(tokens), allocator)
	pos := 0
	err = parse_section(tokens, &pos, &nodes, "")
	return
}

parse_section :: proc(
	tokens: []Token,
	pos: ^int,
	nodes: ^[dynamic]Node,
	end_tag: string,
) -> Render_Error {
	for pos^ < len(tokens) {
		tok := tokens[pos^]

		switch tok.kind {
		case .Text:
			append(nodes, Node{kind = .Text, text = tok.value, first_child = -1})
			pos^ += 1

		case .Variable:
			append(nodes, Node{kind = .Variable, key = tok.value, first_child = -1})
			pos^ += 1

		case .Unescaped:
			append(nodes, Node{kind = .Unescaped, key = tok.value, first_child = -1})
			pos^ += 1

		case .Comment:
			pos^ += 1

		case .Section_Open:
			pos^ += 1
			idx := len(nodes)
			append(nodes, Node{kind = .Section, key = tok.value, first_child = -1})
			err := parse_section(tokens, pos, nodes, tok.value)
			if err != nil do return err
			nodes[idx].first_child = idx + 1
			nodes[idx].child_count = len(nodes) - idx - 1

		case .Inverted_Open:
			pos^ += 1
			idx := len(nodes)
			append(nodes, Node{kind = .Inverted, key = tok.value, first_child = -1})
			err := parse_section(tokens, pos, nodes, tok.value)
			if err != nil do return err
			nodes[idx].first_child = idx + 1
			nodes[idx].child_count = len(nodes) - idx - 1

		case .Section_Close:
			if end_tag != "" && tok.value == end_tag {
				pos^ += 1
				return nil
			}
			if end_tag == "" {
				return Syntax_Error {
					msg = fmt.tprintf("unexpected {{/%s}}", tok.value),
					pos = tok.pos,
				}
			}
			return Syntax_Error {
				msg = fmt.tprintf("expected {{/%s}}, got {{/%s}}", end_tag, tok.value),
				pos = tok.pos,
			}

		case .Partial:
			append(
				nodes,
				Node {
					kind = .Partial,
					key = tok.value,
					is_dynamic = tok.is_dynamic,
					first_child = -1,
				},
			)
			pos^ += 1

		case .Parent:
			pos^ += 1
			idx := len(nodes)
			append(nodes, Node{kind = .Parent, key = tok.value, first_child = -1})
			err := parse_section(tokens, pos, nodes, tok.value)
			if err != nil do return err
			nodes[idx].first_child = idx + 1
			nodes[idx].child_count = len(nodes) - idx - 1

		case .Block_Open:
			pos^ += 1
			idx := len(nodes)
			append(nodes, Node{kind = .Block, key = tok.value, first_child = -1})
			err := parse_section(tokens, pos, nodes, tok.value)
			if err != nil do return err
			nodes[idx].first_child = idx + 1
			nodes[idx].child_count = len(nodes) - idx - 1
		}
	}

	if end_tag != "" {
		return Syntax_Error{msg = fmt.tprintf("unclosed section '{{#%s}}'", end_tag)}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Renderer — walk node array against context stack, write to builder
// ---------------------------------------------------------------------------

render_nodes :: proc(
	all_nodes: []Node,
	nodes: []Node,
	ctx: ^[dynamic]any,
	partials: map[string]Template,
	b: ^strings.Builder,
	blocks: map[string]Block_Override = nil,
) -> Render_Error {
	i := 0
	for i < len(nodes) {
		node := nodes[i]
		switch node.kind {
		case .Text:
			strings.write_string(b, node.text)
			i += 1

		case .Variable:
			val := resolve_name(node.key, ctx[:])
			write_value(b, val, escape = true)
			i += 1

		case .Unescaped:
			val := resolve_name(node.key, ctx[:])
			write_value(b, val, escape = false)
			i += 1

		case .Section:
			val := resolve_name(node.key, ctx[:])
			if is_truthy(val) {
				children := all_nodes[node.first_child:node.first_child + node.child_count]
				elem_info, count, data := list_info(val)
				if elem_info != nil {
					for j in 0..<count {
						elem_ptr := rawptr(uintptr(data) + uintptr(j) * uintptr(elem_info.size))
						append(ctx, any{elem_ptr, elem_info.id})
						err := render_nodes(all_nodes, children, ctx, partials, b, blocks)
						pop(ctx)
						if err != nil do return err
					}
				} else {
					append(ctx, val)
					err := render_nodes(all_nodes, children, ctx, partials, b, blocks)
					pop(ctx)
					if err != nil do return err
				}
			}
			i += 1 + node.child_count

		case .Inverted:
			val := resolve_name(node.key, ctx[:])
			if !is_truthy(val) {
				children := all_nodes[node.first_child:node.first_child + node.child_count]
				err := render_nodes(all_nodes, children, ctx, partials, b, blocks)
				if err != nil do return err
			}
			i += 1 + node.child_count

		case .Partial:
			name := node.key
			if node.is_dynamic {
				val := resolve_name(node.key, ctx[:])
				name = any_to_string(val)
			}
			pt, found := partials[name]
			if found {
				err := render_nodes(pt.nodes[:], pt.nodes[:], ctx, partials, b)
				if err != nil do return err
			}
			i += 1

		case .Block:
			rendered_override := false
			if blocks != nil {
				if o, ok := blocks[node.key]; ok {
					children := o.all_nodes[o.first:o.first + o.count]
					err := render_nodes(o.all_nodes, children, ctx, partials, b)
					if err != nil do return err
					rendered_override = true
				}
			}
			if !rendered_override {
				children := all_nodes[node.first_child:node.first_child + node.child_count]
				err := render_nodes(all_nodes, children, ctx, partials, b, blocks)
				if err != nil do return err
			}
			i += 1 + node.child_count

		case .Parent:
			parent_children := all_nodes[node.first_child:node.first_child + node.child_count]
			merged := merge_block_overrides(parent_children, all_nodes, blocks)
			pt, found := partials[node.key]
			if found {
				err := render_nodes(pt.nodes[:], pt.nodes[:], ctx, partials, b, merged)
				if err != nil do return err
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
				result[child.key] = Block_Override{
					all_nodes = all_nodes,
					first = child.first_child,
					count = child.child_count,
				}
			}
			i += 1 + child.child_count
		} else {
			i += 1
		}
	}

	return result
}

