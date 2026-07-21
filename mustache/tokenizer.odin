package mustache

import "core:strings"

Token_Kind :: enum {
	Text,
	Variable,
	Unescaped,
	Section_Open,
	Inverted_Open,
	Section_Close,
	Comment,
	Partial,
	Parent,
	Block_Open,
}

Token :: struct {
	kind:       Token_Kind,
	value:      string,
	is_dynamic: bool,
	indent:     string,
	pos:        int,
}

tokenize :: proc(
	src: string,
	allocator := context.allocator,
) -> (
	tokens: [dynamic]Token,
	err: Error,
) {
	tokens = make([dynamic]Token, 0, 8, allocator)

	i := 0
	text_start := 0

	for i < len(src) {
		if src[i] == '{' && i + 1 < len(src) && src[i + 1] == '{' {
			if i > text_start {
				append(&tokens, Token{kind = .Text, value = src[text_start:i], pos = text_start})
			}

			tag_pos := i

			if i + 2 < len(src) && src[i + 2] == '{' {
				content_start := i + 3
				idx := strings.index(src[content_start:], "}}}")
				if idx < 0 {
					return tokens, Error_Body {
						msg = "unclosed triple mustache '{{{'",
						pos = tag_pos,
						kind = .Syntax,
					}
				}
				close := content_start + idx
				key := strings.trim_space(src[content_start:close])
				append(&tokens, Token{kind = .Unescaped, value = key, pos = tag_pos})
				i = close + 3
				text_start = i
			} else {
				content_start := i + 2
				sigil: byte = 0
				if content_start < len(src) {
					sigil = src[content_start]
				}

				kind: Token_Kind
				key_start := content_start

				switch sigil {
				case '&':
					kind = .Unescaped; key_start = content_start + 1
				case '#':
					kind = .Section_Open; key_start = content_start + 1
				case '^':
					kind = .Inverted_Open; key_start = content_start + 1
				case '/':
					kind = .Section_Close; key_start = content_start + 1
				case '!':
					kind = .Comment; key_start = content_start + 1
				case '>':
					kind = .Partial; key_start = content_start + 1
				case '<':
					kind = .Parent; key_start = content_start + 1
				case '$':
					kind = .Block_Open; key_start = content_start + 1
				case:
					kind = .Variable
				}

				close_idx := strings.index(src[key_start:], "}}")
			if close_idx < 0 {
				return tokens, Error_Body {
					msg = "unclosed tag '{{'",
					pos = tag_pos,
					kind = .Syntax,
				}
			}
				close := key_start + close_idx

				content := src[key_start:close]

				if kind == .Comment {
					append(&tokens, Token{kind = .Comment, value = content, pos = tag_pos})
				} else if kind == .Partial {
					trimmed := strings.trim_space(content)
					is_dyn := false
					if len(trimmed) > 0 && trimmed[0] == '*' {
						is_dyn = true
						trimmed = strings.trim_space(trimmed[1:])
					}
					append(
						&tokens,
						Token {
							kind = .Partial,
							value = trimmed,
							is_dynamic = is_dyn,
							pos = tag_pos,
						},
					)
				} else {
					append(
						&tokens,
						Token{kind = kind, value = strings.trim_space(content), pos = tag_pos},
					)
				}

				i = close + 2
				text_start = i
			}
		} else {
			i += 1
		}
	}

	if i > text_start {
		append(&tokens, Token{kind = .Text, value = src[text_start:i], pos = text_start})
	}

	trim_standalone_whitespace(&tokens)
	return tokens, nil
}

// ---------------------------------------------------------------------------
// Standalone whitespace handling
// ---------------------------------------------------------------------------

trim_standalone_whitespace :: proc(tokens: ^[dynamic]Token) {
	n := len(tokens)

	// First pass: detect standalone status using original token values
	li_buf := make([dynamic]int, n, context.temp_allocator)
	defer delete(li_buf)
	ri_buf := make([dynamic]int, n, context.temp_allocator)
	defer delete(ri_buf)

	for i := 0; i < n; i += 1 {
		li_buf[i] = -1
		ri_buf[i] = -1
	}

	for i := 0; i < n; i += 1 {
		should_trim_whitespace(tokens[i].kind) or_continue

		left_ok, li := check_left(tokens[:], i)
		right_ok, ri := check_right(tokens[:], i)

		if left_ok && right_ok {
			li_buf[i] = li
			ri_buf[i] = ri
		}
	}

	// Second pass: apply trims left-to-right
	// Track which text tokens have been trimmed to avoid double-trimming
	left_done := make([dynamic]bool, n, context.temp_allocator)
	defer delete(left_done)
	right_done := make([dynamic]bool, n, context.temp_allocator)
	defer delete(right_done)

	for i := 0; i < n; i += 1 {
		should_trim_whitespace(tokens[i].kind) or_continue
		li := li_buf[i]
		ri := ri_buf[i]
		if li < 0 && ri < 0 {
			continue
		}

		if li >= 0 && !left_done[li] {
			left_done[li] = true
			text := tokens[li].value
			nl := strings.last_index_byte(text, '\n')
			if tokens[i].kind == .Partial ||
			   tokens[i].kind == .Parent ||
			   tokens[i].kind == .Block_Open {
				tokens[i].indent = text[nl + 1:] if nl >= 0 else text
			}
			tokens[li].value = text[:nl + 1] if nl >= 0 else ""
		}

		if ri >= 0 && !right_done[ri] {
			right_done[ri] = true
			// When a Block_Open and its Section_Close are adjacent (e.g.
			// {{$block}}{{/block}}\n), the close tag is the one that
			// should consume the trailing newline — not the block open.
			// Skip the right-trim if a Section_Close sits between this
			// tag and its right text, or if this IS the Section_Close
			// immediately following a Block_Open (the close handles it).
			skip := false
			if tokens[i].kind == .Block_Open {
				for k := i + 1; k < ri; k += 1 {
					if tokens[k].kind == .Section_Close {
						skip = true
						break
					}
				}
			}
			if tokens[i].kind == .Section_Close && i > 0 && tokens[i - 1].kind == .Block_Open {
				skip = true
			}
			if !skip {
				text := tokens[ri].value
				nl := strings.index_byte(text, '\n')
				tokens[ri].value = text[nl + 1:] if nl >= 0 else ""
			}
		}
	}
}

check_left :: proc(tokens: []Token, i: int) -> (ok: bool, text_idx: int) {
	j := i - 1
	for j >= 0 {
		if tokens[j].kind == .Text {
			text := tokens[j].value
			if len(text) == 0 {
				j -= 1
				continue
			}
			nl := strings.last_index_byte(text, '\n')
			if nl >= 0 {
				return strings.trim_space(text[nl + 1:]) == "", j
			}
			if j == 0 {
				return strings.trim_space(text) == "", j
			}
			return false, -1
		} else if should_trim_whitespace(tokens[j].kind) {
			j -= 1
		} else {
			return false, -1
		}
	}
	return true, -1
}

check_right :: proc(tokens: []Token, i: int) -> (ok: bool, text_idx: int) {
	j := i + 1
	for j < len(tokens) {
		if tokens[j].kind == .Text {
			text := tokens[j].value
			if len(text) == 0 {
				j += 1
				continue
			}
			nl := strings.index_byte(text, '\n')
			if nl >= 0 {
				return strings.trim_space(text[:nl]) == "", j
			}
			if j == len(tokens) - 1 {
				return strings.trim_space(text) == "", j
			}
			return false, -1
		} else if should_trim_whitespace(tokens[j].kind) {
			j += 1
		} else {
			return false, -1
		}
	}
	return true, -1
}

should_trim_whitespace :: proc(kind: Token_Kind) -> bool {
	switch kind {
	case .Section_Open, .Inverted_Open, .Section_Close, .Comment, .Partial, .Parent, .Block_Open:
		return true
	case .Text, .Variable, .Unescaped:
		return false
	}
	return false
}

