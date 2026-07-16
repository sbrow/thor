#+feature dynamic-literals
#+test
package main

import "core:strings"
import "core:testing"

@(test)
test_parse_def_line :: proc(t: ^testing.T) {
	// sidenote definition
	id, text, kind, ok := parse_def_line("[^foo]: bar baz")
	testing.expect(t, ok)
	testing.expect(t, id == "foo")
	testing.expect(t, text == "bar baz")
	testing.expect(t, kind == .Sidenote)

	// marginnote definition
	id, text, kind, ok = parse_def_line("[*baz]: qux")
	testing.expect(t, ok)
	testing.expect(t, id == "baz")
	testing.expect(t, text == "qux")
	testing.expect(t, kind == .Marginnote)

	// plain text is not a definition
	_, _, _, ok = parse_def_line("regular text")
	testing.expect(t, !ok)

	// a bracket that is not a note (e.g. reference-link style) is ignored
	_, _, _, ok = parse_def_line("[link]: url")
	testing.expect(t, !ok)
}

@(test)
test_strip_definitions :: proc(t: ^testing.T) {
	body := "Intro[^a] and [*b].\n\n[^a]: a side\n\n[*b]: a margin\n"
	clean, sn_defs, mn_defs := strip_definitions(body)
	defer {
		delete(clean)
		delete(sn_defs["a"])
		delete(sn_defs)
		delete(mn_defs["b"])
		delete(mn_defs)
	}

	// references stay; definitions are removed
	testing.expect(t, strings.contains(clean, "Intro[^a]"))
	testing.expect(t, strings.contains(clean, "[*b]"))
	testing.expect(t, !strings.contains(clean, "[^a]:"))
	testing.expect(t, !strings.contains(clean, "[*b]:"))

	// routed to the correct map by sigil
	sa, sa_ok := sn_defs["a"]
	testing.expect(t, sa_ok)
	testing.expect(t, sa == "a side")

	mb, mb_ok := mn_defs["b"]
	testing.expect(t, mb_ok)
	testing.expect(t, mb == "a margin")

	// ids do not leak across maps
	_, leaked := sn_defs["b"]
	testing.expect(t, !leaked)
	_, leaked2 := mn_defs["a"]
	testing.expect(t, !leaked2)
}

@(test)
test_inject_notes :: proc(t: ^testing.T) {
	html := "Text[^a] more [*b] end."
	sn_defs := map[string]string {
		"a" = "side note",
	}
	defer delete(sn_defs)
	mn_defs := map[string]string {
		"b" = "margin note",
	}
	defer delete(mn_defs)

	out := inject_notes(html, sn_defs, mn_defs)

	// sidenote: numbered, fn- prefix, .sidenote span, rendered text
	testing.expect(
		t,
		strings.contains(out, `for="fn-a" class="margin-toggle sidenote-number"></label>`),
	)
	testing.expect(t, strings.contains(out, `class="sidenote"`))
	testing.expect(t, strings.contains(out, "side note"))

	// marginnote: unnumbered, mn- prefix, .marginnote span, rendered text
	testing.expect(t, strings.contains(out, `for="mn-b" class="margin-toggle"></label>`))
	testing.expect(t, strings.contains(out, `class="marginnote"`))
	testing.expect(t, strings.contains(out, "margin note"))
}

@(test)
test_inject_notes_no_defs :: proc(t: ^testing.T) {
	html := "No notes here."
	sn := make(map[string]string)
	mn := make(map[string]string)
	testing.expect(t, inject_notes(html, sn, mn) == html)
}

@(test)
test_inject_notes_missing_ref :: proc(t: ^testing.T) {
	html := "Ref[^missing] and [*missing] end."
	sn := map[string]string {
		"other" = "x",
	}
	defer delete_map(sn)
	mn := map[string]string {
		"other2" = "y",
	}
	defer delete_map(mn)

	out := inject_notes(html, sn, mn)

	// references with no matching definition are left as literal text
	testing.expect(t, len(out) > 2)
	testing.expect(t, strings.contains(out, "[^missing]"))
	testing.expect(t, strings.contains(out, "[*missing]"))
}

