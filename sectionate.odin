package main

import "core:strings"

wrap_sections :: proc(html: string) -> string {
	H2 :: "<h2"

	parts: [dynamic]string
	defer delete(parts)
	pos := 0
	search_pos := 0

	for {
		rel := strings.index(html[search_pos:], H2)
		if rel < 0 {
			break
		}
		idx := search_pos + rel

		if idx > pos {
			append(&parts, "<section>")
			append(&parts, html[pos:idx])
			append(&parts, "</section>")
		}

		pos = idx
		search_pos = idx + len(H2)
	}

	if pos < len(html) {
		append(&parts, "<section>")
		append(&parts, html[pos:])
		append(&parts, "</section>")
	}

	if len(parts) == 0 {
		return html
	}
	return strings.join(parts[:], "")
}
