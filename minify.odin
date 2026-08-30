package main

import ts "treesitter"

import "core:log"
import "core:strings"

PRESERVE_TAGS :: [?]string{"pre", "code", "textarea"}

Range :: struct {
	start: u32,
	end:   u32,
}

minify_html :: proc(source: string) -> string {
	gc := ts.ensure_parser("html")
	if gc == nil {
		return source
	}

	source_c := strings.clone_to_cstring(source)
	defer delete(source_c)

	tree := ts.parser_parse_string(gc.parser, nil, source_c, u32(len(source)))
	if tree == nil {
		return source
	}
	defer ts.tree_delete(tree)

	root := ts.tree_root_node(tree)

	if ts.node_has_error(root) {
		log.warnf("minify: HTML parse errors, skipping minification")
		return source
	}

	comments: [dynamic]Range
	defer delete(comments)
	preserves: [dynamic]Range
	defer delete(preserves)
	styles: [dynamic]Range
	defer delete(styles)

	collect_html_ranges(root, source, &comments, &preserves, &styles)

	sb := strings.builder_make()

	ci := 0
	pi := 0
	si := 0
	i := 0
	last_written: u8 = 0

	for i < len(source) {
		if pi < len(preserves) && u32(i) >= preserves[pi].start {
			p := preserves[pi]
			segment := source[i:p.end]
			strings.write_string(&sb, segment)
			if len(segment) > 0 {
				last_written = segment[len(segment) - 1]
			}
			i = int(p.end)
			pi += 1
			continue
		}

		if si < len(styles) && u32(i) >= styles[si].start {
			s := styles[si]
			// NOTE: minify_css may return either a fresh allocation or the
			// input slice unchanged (on parser failure), so the result is not
			// freed here — matching this package's one-shot allocation style.
			minified := minify_css(source[i:s.end])
			strings.write_string(&sb, minified)
			if len(minified) > 0 {
				last_written = minified[len(minified) - 1]
			}
			i = int(s.end)
			si += 1
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
	node: ts.Node,
	source: string,
	comments: ^[dynamic]Range,
	preserves: ^[dynamic]Range,
	styles: ^[dynamic]Range,
) {
	child_count := ts.node_named_child_count(node)
	for i in 0 ..< child_count {
		child := ts.node_named_child(node, u32(i))
		type_str := string(ts.node_type(child))

		if type_str == "comment" {
			append(
				comments,
				Range{start = ts.node_start_byte(child), end = ts.node_end_byte(child)},
			)
		} else if type_str == "style_element" {
			// Preserve the <style> tags but minify the CSS body (the raw_text
			// child) via the CSS-aware pass.
			raw, ok := style_raw_text(child)
			if ok {
				append(
					styles,
					Range{start = ts.node_start_byte(raw), end = ts.node_end_byte(raw)},
				)
			}
		} else if type_str == "script_element" {
			append(
				preserves,
				Range{start = ts.node_start_byte(child), end = ts.node_end_byte(child)},
			)
		} else if type_str == "element" {
			tag := html_tag_name(child, source)
			if is_preserve_tag(tag) {
				append(
					preserves,
					Range{start = ts.node_start_byte(child), end = ts.node_end_byte(child)},
				)
			} else {
				collect_html_ranges(child, source, comments, preserves, styles)
			}
		} else {
			collect_html_ranges(child, source, comments, preserves, styles)
		}
	}
}

// style_raw_text returns the raw_text (CSS body) child of a style_element.
// ok is false for an empty <style></style>, which has no raw_text child.
style_raw_text :: proc(style_element: ts.Node) -> (raw: ts.Node, ok: bool) {
	child_count := ts.node_named_child_count(style_element)
	for i in 0 ..< child_count {
		child := ts.node_named_child(style_element, u32(i))
		if string(ts.node_type(child)) == "raw_text" {
			return child, true
		}
	}
	return {}, false
}

html_tag_name :: proc(element: ts.Node, source: string) -> string {
	child_count := ts.node_named_child_count(element)
	for i in 0 ..< child_count {
		child := ts.node_named_child(element, u32(i))
		if string(ts.node_type(child)) == "start_tag" {
			tag_child_count := ts.node_named_child_count(child)
			for j in 0 ..< tag_child_count {
				tag_child := ts.node_named_child(child, u32(j))
				if string(ts.node_type(tag_child)) == "tag_name" {
					start := ts.node_start_byte(tag_child)
					end := ts.node_end_byte(tag_child)
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
	gc := ts.ensure_parser("css")
	if gc == nil {
		return source
	}

	source_c := strings.clone_to_cstring(source)
	defer delete(source_c)

	tree := ts.parser_parse_string(gc.parser, nil, source_c, u32(len(source)))
	if tree == nil {
		return source
	}
	defer ts.tree_delete(tree)

	root := ts.tree_root_node(tree)

	if ts.node_has_error(root) {
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

			// Emit a single separating space, but never a leading space
			// (last_written == 0), a doubled space (last_written == ' ',
			// which happens when a stripped comment sits between two
			// whitespace runs), or one adjacent to a delimiter.
			if last_written != 0 && last_written != ' ' &&
			   !is_css_delim(last_written) && !is_css_delim(next) {
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

collect_css_comments :: proc(node: ts.Node, comments: ^[dynamic]Range) {
	child_count := ts.node_named_child_count(node)
	for i in 0 ..< child_count {
		child := ts.node_named_child(node, u32(i))
		if string(ts.node_type(child)) == "comment" {
			append(
				comments,
				Range{start = ts.node_start_byte(child), end = ts.node_end_byte(child)},
			)
		} else {
			collect_css_comments(child, comments)
		}
	}
}
