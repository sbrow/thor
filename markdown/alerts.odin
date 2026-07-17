#+feature dynamic-literals
package markdown

import "core:strings"

ALERT_EMOJIS: map[string]string = {
	"note"      = "ℹ️",
	"tip"       = "💡",
	"important" = "❗",
	"warning"   = "⚠️",
	"caution"   = "❗",
}

inject_alerts :: proc(html: string) -> string {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	remaining := html

	for {
		bq_start := strings.index(remaining, "<blockquote>")
		if bq_start < 0 {
			strings.write_string(&sb, remaining)
			break
		}

		bq_close := strings.index(remaining, "</blockquote>")
		if bq_close < 0 {
			strings.write_string(&sb, remaining)
			break
		}

		bq_end := bq_close + len("</blockquote>")
		bq := remaining[bq_start:bq_end]

		strings.write_string(&sb, remaining[:bq_start])
		transform_alert(&sb, bq)

		remaining = remaining[bq_end:]
	}

	return strings.to_string(sb)
}

transform_alert :: proc(sb: ^strings.Builder, bq: string) {
	pos := len("<blockquote>")
	for pos < len(bq) &&
	    (bq[pos] == '\n' || bq[pos] == '\r' || bq[pos] == ' ' || bq[pos] == '\t') {
		pos += 1
	}

	if pos + 4 >= len(bq) ||
	   bq[pos] != '<' ||
	   bq[pos + 1] != 'p' ||
	   bq[pos + 2] != '>' ||
	   bq[pos + 3] != '[' ||
	   bq[pos + 4] != '!' {
		strings.write_string(sb, bq)
		return
	}

	close := strings.index(bq[pos + 5:], "]")
	if close < 0 {
		strings.write_string(sb, bq)
		return
	}

	type_raw := bq[pos + 5:pos + 5 + close]
	type_lower := strings.to_lower(type_raw, context.temp_allocator)

	emoji, found := ALERT_EMOJIS[type_lower]
	if !found {
		strings.write_string(sb, bq)
		return
	}

	after_type := pos + 5 + close + 1

	content_start := after_type
	if content_start < len(bq) && (bq[content_start] == '+' || bq[content_start] == '-') {
		content_start += 1
	}
	if content_start < len(bq) && bq[content_start] == ' ' {
		content_start += 1
	}

	rest := bq[content_start:]

	strings.write_string(sb, `<blockquote class="alert alert-`)
	strings.write_string(sb, type_lower)
	strings.write_string(sb, `">`)
	strings.write_string(sb, "\n")
	strings.write_string(sb, `<p class="alert-title">`)
	strings.write_string(sb, emoji)
	strings.write_string(sb, " ")
	strings.write_string(sb, rest)
}

