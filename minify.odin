package main

import "core:log"
import "core:strings"

PRESERVE_TAGS :: [?]string{"pre", "code", "textarea"}

Range :: struct {
	start: u32,
	end:   u32,
}

minify_html :: proc(source: string) -> string {
	gc := ensure_parser("html")
	if gc == nil {
		return source
	}

	source_c := strings.clone_to_cstring(source)
	defer delete(source_c)

	tree := ts_parser_parse_string(gc.parser, nil, source_c, u32(len(source)))
	if tree == nil {
		return source
	}
	defer ts_tree_delete(tree)

	root := ts_tree_root_node(tree)

	if ts_node_has_error(root) {
		log.warnf("minify: HTML parse errors, skipping minification")
		return source
	}

	comments: [dynamic]Range
	defer delete(comments)
	preserves: [dynamic]Range
	defer delete(preserves)

	collect_html_ranges(root, source, &comments, &preserves)

	sb := strings.builder_make()

	ci := 0
	pi := 0
	i := 0
	last_written: u8 = 0

	for i < len(source) {
		if pi < len(preserves) && u32(i) >= preserves[pi].start {
			p := preserves[pi]
			segment := source[i:p.end]
			strings.write_string(&sb, segment)
			if len(segment) > 0 {
				last_written = segment[len(segment)-1]
			}
			i = int(p.end)
			pi += 1
			continue
		}

		if ci < len(comments) && u32(i) >= comments[ci].start {
			i = int(comments[ci].end)
			ci += 1
			continue
		}

		c := source[i]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			j := i + 1
			for j < len(source) {
				c2 := source[j]
				if c2 != ' ' && c2 != '\t' && c2 != '\n' && c2 != '\r' {
					break
				}
				j += 1
			}
			next: u8 = 0
			if j < len(source) {
				next = source[j]
			}
			if last_written != '>' || next != '<' {
				strings.write_byte(&sb, ' ')
				last_written = ' '
			}
			i = j
		} else {
			strings.write_byte(&sb, c)
			last_written = c
			i += 1
		}
	}

	return strings.to_string(sb)
}

collect_html_ranges :: proc(
	node: TSNode,
	source: string,
	comments: ^[dynamic]Range,
	preserves: ^[dynamic]Range,
) {
	child_count := ts_node_named_child_count(node)
	for i in 0..<child_count {
		child := ts_node_named_child(node, u32(i))
		type_str := string(ts_node_type(child))

		if type_str == "comment" {
			append(comments, Range{
				start = ts_node_start_byte(child),
				end = ts_node_end_byte(child),
			})
		} else if type_str == "script_element" || type_str == "style_element" {
			append(preserves, Range{
				start = ts_node_start_byte(child),
				end = ts_node_end_byte(child),
			})
		} else if type_str == "element" {
			tag := html_tag_name(child, source)
			if is_preserve_tag(tag) {
				append(preserves, Range{
					start = ts_node_start_byte(child),
					end = ts_node_end_byte(child),
				})
			} else {
				collect_html_ranges(child, source, comments, preserves)
			}
		} else {
			collect_html_ranges(child, source, comments, preserves)
		}
	}
}

html_tag_name :: proc(element: TSNode, source: string) -> string {
	child_count := ts_node_named_child_count(element)
	for i in 0..<child_count {
		child := ts_node_named_child(element, u32(i))
		if string(ts_node_type(child)) == "start_tag" {
			tag_child_count := ts_node_named_child_count(child)
			for j in 0..<tag_child_count {
				tag_child := ts_node_named_child(child, u32(j))
				if string(ts_node_type(tag_child)) == "tag_name" {
					start := ts_node_start_byte(tag_child)
					end := ts_node_end_byte(tag_child)
					return source[start:end]
				}
			}
		}
	}
	return ""
}

is_preserve_tag :: proc(tag: string) -> bool {
	for t in PRESERVE_TAGS {
		if tag == t do return true
	}
	return false
}

CSS_DELIMS :: [?]u8{'{', '}', ':', ';', ','}

is_css_delim :: proc(c: u8) -> bool {
	for d in CSS_DELIMS {
		if c == d do return true
	}
	return false
}

minify_css :: proc(source: string) -> string {
	gc := ensure_parser("css")
	if gc == nil {
		return source
	}

	source_c := strings.clone_to_cstring(source)
	defer delete(source_c)

	tree := ts_parser_parse_string(gc.parser, nil, source_c, u32(len(source)))
	if tree == nil {
		return source
	}
	defer ts_tree_delete(tree)

	root := ts_tree_root_node(tree)

	if ts_node_has_error(root) {
		log.warnf("minify: CSS parse errors, skipping minification")
		return source
	}

	comments: [dynamic]Range
	defer delete(comments)

	collect_css_comments(root, &comments)

	sb := strings.builder_make()

	ci := 0
	i := 0
	last_written: u8 = 0

	for i < len(source) {
		if ci < len(comments) && u32(i) >= comments[ci].start {
			i = int(comments[ci].end)
			ci += 1
			continue
		}

		c := source[i]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			j := i + 1
			for j < len(source) {
				c2 := source[j]
				if c2 != ' ' && c2 != '\t' && c2 != '\n' && c2 != '\r' {
					break
				}
				j += 1
			}

			next: u8 = 0
			if j < len(source) {
				next = source[j]
			}

			if !is_css_delim(last_written) && !is_css_delim(next) {
				strings.write_byte(&sb, ' ')
				last_written = ' '
			}
			i = j
		} else {
			strings.write_byte(&sb, c)
			last_written = c
			i += 1
		}
	}

	return strings.to_string(sb)
}

collect_css_comments :: proc(node: TSNode, comments: ^[dynamic]Range) {
	child_count := ts_node_named_child_count(node)
	for i in 0..<child_count {
		child := ts_node_named_child(node, u32(i))
		if string(ts_node_type(child)) == "comment" {
			append(comments, Range{
				start = ts_node_start_byte(child),
				end = ts_node_end_byte(child),
			})
		} else {
			collect_css_comments(child, comments)
		}
	}
}
