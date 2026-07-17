package markdown

import "core:strings"

wrap_sections :: proc(html: string) -> string {
	H2 :: "<h2"

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	pos := 0
	search_pos := 0
	found := false

	for {
		rel := strings.index(html[search_pos:], H2)
		if rel < 0 {
			break
		}
		idx := search_pos + rel
		found = true

		if idx > pos {
			strings.write_string(&sb, "<section>")
			strings.write_string(&sb, html[pos:idx])
			strings.write_string(&sb, "</section>")
		}

		pos = idx
		search_pos = idx + len(H2)
	}

	if pos < len(html) {
		strings.write_string(&sb, "<section>")
		strings.write_string(&sb, html[pos:])
		strings.write_string(&sb, "</section>")
		found = true
	}

	if found {
		return strings.to_string(sb)
	} else {
		return html
	}
}

