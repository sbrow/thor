#+feature dynamic-literals
package markdown

import "core:fmt"
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
		strings.write_string(&sb, transform_alert(bq))

		remaining = remaining[bq_end:]
	}

	return strings.to_string(sb)
}

transform_alert :: proc(bq: string) -> string {
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
		return bq
	}

	close := strings.index(bq[pos + 5:], "]")
	if close < 0 {
		return bq
	}

	type_raw := bq[pos + 5:pos + 5 + close]
	type_lower := strings.to_lower(type_raw)

	emoji, found := ALERT_EMOJIS[type_lower]
	if !found {
		return bq
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

	return fmt.aprintf(
		`<blockquote class="alert alert-%s">
<p class="alert-title">%s %s`,
		type_lower,
		emoji,
		rest,
	)
}

