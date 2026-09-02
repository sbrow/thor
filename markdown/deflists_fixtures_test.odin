#+test
package markdown

import "core:testing"

// Fixture-driven tests for convert_deflists. Every fixture is exact-matched
// against its oracle in testdata/deflists/expected/. See
// testdata/deflists/reference/README.md for how each expected file was decided
// (cross-checked against Pandoc and Hugo/Goldmark).
//
// The fixture inputs are the definition-list examples from
// https://www.markdownlang.com/extended/definition-lists.html
//
// Provenance of each expected file:
//   01,02,08,09  Pandoc and Hugo agree; oracle = that agreed HTML.
//   06           Both agree it is NOT a deflist; convert_deflists passes the
//                markdown through unchanged, so expected = the raw input.
//   07           CommonMark's <4-space marker rule: we accept the 2-space colon
//                (Pandoc does; Hugo does not).
//   05           Block nesting is unsupported; our flatten happens to match
//                Pandoc's output exactly.
//   03,04        Block content in definitions is unsupported; expected captures
//                our current degraded behavior (a <dl> for the term/first line,
//                the rest falling through as markdown) as a regression guard.
Deflist_Fixture :: struct {
	name:     string,
	input:    string,
	expected: string,
}

@(test)
test_deflist_fixtures :: proc(t: ^testing.T) {
	cases := []Deflist_Fixture {
		{
			"01-basic",
			#load(#directory + "testdata/deflists/01-basic.md", string),
			#load(#directory + "testdata/deflists/expected/01-basic.html", string),
		},
		{
			"02-multiple-defs",
			#load(#directory + "testdata/deflists/02-multiple-defs.md", string),
			#load(#directory + "testdata/deflists/expected/02-multiple-defs.html", string),
		},
		{
			"03-multiline-def",
			#load(#directory + "testdata/deflists/03-multiline-def.md", string),
			#load(#directory + "testdata/deflists/expected/03-multiline-def.html", string),
		},
		{
			"04-markdown-in-def",
			#load(#directory + "testdata/deflists/04-markdown-in-def.md", string),
			#load(#directory + "testdata/deflists/expected/04-markdown-in-def.html", string),
		},
		{
			"05-nested",
			#load(#directory + "testdata/deflists/05-nested.md", string),
			#load(#directory + "testdata/deflists/expected/05-nested.html", string),
		},
		{
			"06-compact",
			#load(#directory + "testdata/deflists/06-compact.md", string),
			#load(#directory + "testdata/deflists/expected/06-compact.html", string),
		},
		{
			"07-extra-space",
			#load(#directory + "testdata/deflists/07-extra-space.md", string),
			#load(#directory + "testdata/deflists/expected/07-extra-space.html", string),
		},
		{
			"08-glossary",
			#load(#directory + "testdata/deflists/08-glossary.md", string),
			#load(#directory + "testdata/deflists/expected/08-glossary.html", string),
		},
		{
			"09-api-params",
			#load(#directory + "testdata/deflists/09-api-params.md", string),
			#load(#directory + "testdata/deflists/expected/09-api-params.html", string),
		},
	}

	for c in cases {
		result := convert_deflists(c.input, context.temp_allocator)
		testing.expectf(
			t,
			result == c.expected,
			"[%s]\n  expected: %q\n  got:      %q",
			c.name,
			c.expected,
			result,
		)
	}
}
