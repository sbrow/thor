#+feature dynamic-literals
package markdown

import "core:fmt"
import "core:strings"

ALERT_STYLES: map[string]string = {
	"note"      = "border-l-blue-500 bg-blue-950/30 text-slate-300",
	"tip"       = "border-l-green-500 bg-green-950/30 text-slate-300",
	"important" = "border-l-purple-500 bg-purple-950/30 text-slate-300",
	"warning"   = "border-l-yellow-500 bg-yellow-950/30 text-slate-300",
	"caution"   = "border-l-red-500 bg-red-950/30 text-slate-300",
}

ALERT_EMOJIS: map[string]string = {
	"note"      = "\xe2\x84\xb9\xef\xb8\x8f",
	"tip"       = "\xf0\x9f\x92\xa1",
	"important" = "\xe2\x9d\x97",
	"warning"   = "\xe2\x9a\xa0\xef\xb8\x8f",
	"caution"   = "\xe2\x9d\x97",
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
	// Skip <blockquote> tag and whitespace
	pos := len("<blockquote>")
	for pos < len(bq) && (bq[pos] == '\n' || bq[pos] == '\r' || bq[pos] == ' ' || bq[pos] == '\t') {
		pos += 1
	}

	// Check for <p>[!
	if pos + 4 >= len(bq) || bq[pos] != '<' || bq[pos + 1] != 'p' || bq[pos + 2] != '>' ||
	   bq[pos + 3] != '[' || bq[pos + 4] != '!' {
		return bq
	}

	// Extract alert type until ]
	close := strings.index(bq[pos + 5:], "]")
	if close < 0 {
		return bq
	}

	type_raw := bq[pos + 5 : pos + 5 + close]
	type_lower := strings.to_lower(type_raw)

	style, has_style := ALERT_STYLES[type_lower]
	emoji, has_emoji := ALERT_EMOJIS[type_lower]
	if !has_style || !has_emoji {
		return bq
	}

	// Position after ]
	after_type := pos + 5 + close + 1

	// Skip optional + or -
	content_start := after_type
	if content_start < len(bq) && (bq[content_start] == '+' || bq[content_start] == '-') {
		content_start += 1
	}
	// Skip space after marker
	if content_start < len(bq) && bq[content_start] == ' ' {
		content_start += 1
	}

	// Rebuild: styled blockquote + bold title paragraph + rest
	rest := bq[content_start:]

	return fmt.aprintf(
		`<blockquote class="alert %s rounded-r py-2">
<p class="font-bold mb-1">%s %s`,
		style,
		emoji,
		rest,
	)
}
