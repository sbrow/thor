#+feature dynamic-literals
#+test
package markdown

import "core:testing"

@(test)
test_alerts_render_properly :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		inject_alerts("<blockquote>\n<p>[!NOTE] Hello.</p>\n</blockquote>"),
		`<blockquote class="alert alert-note">
<p class="alert-title">ℹ️ Hello.</p>
</blockquote>`,
	)

	testing.expect_value(
		t,
		inject_alerts("<blockquote>\n<p>[!TIP] Be smart.</p>\n</blockquote>"),
		`<blockquote class="alert alert-tip">
<p class="alert-title">💡 Be smart.</p>
</blockquote>`,
	)

	testing.expect_value(
		t,
		inject_alerts("<blockquote>\n<p>[!CAUTION] Danger!</p>\n</blockquote>"),
		`<blockquote class="alert alert-caution">
<p class="alert-title">❗ Danger!</p>
</blockquote>`,
	)
}

@(test)
test_non_alerts_pass_through_inject_alerts :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		inject_alerts("<blockquote>\n<p>Just a quote.</p>\n</blockquote>"),
		"<blockquote>\n<p>Just a quote.</p>\n</blockquote>",
	)

	testing.expect_value(
		t,
		inject_alerts("<blockquote>\n<p>[!UNKNOWN] Nope.</p>\n</blockquote>"),
		"<blockquote>\n<p>[!UNKNOWN] Nope.</p>\n</blockquote>",
	)

	testing.expect_value(
		t,
		inject_alerts("<p>No blockquote here.</p>"),
		"<p>No blockquote here.</p>",
	)

	testing.expect_value(t, inject_alerts(""), "")
}

@(test)
test_case_insensitive_alerts_render :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		inject_alerts("<blockquote>\n<p>[!Note] Mixed case.</p>\n</blockquote>"),
		`<blockquote class="alert alert-note">
<p class="alert-title">ℹ️ Mixed case.</p>
</blockquote>`,
	)

	testing.expect_value(
		t,
		inject_alerts("<blockquote>\n<p>[!NOTE] Upper case.</p>\n</blockquote>"),
		`<blockquote class="alert alert-note">
<p class="alert-title">ℹ️ Upper case.</p>
</blockquote>`,
	)
}

@(test)
test_multiple_alerts_render_together :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		inject_alerts(
			"<blockquote>\n<p>[!NOTE] First.</p>\n</blockquote>\n<blockquote>\n<p>[!TIP] Second.</p>\n</blockquote>",
		),
		`<blockquote class="alert alert-note">
<p class="alert-title">ℹ️ First.</p>
</blockquote>
<blockquote class="alert alert-tip">
<p class="alert-title">💡 Second.</p>
</blockquote>`,
	)

	testing.expect_value(
		t,
		inject_alerts(
			"<blockquote>\n<p>Regular.</p>\n</blockquote>\n<blockquote>\n<p>[!WARNING] Alert!</p>\n</blockquote>",
		),
		`<blockquote>
<p>Regular.</p>
</blockquote>
<blockquote class="alert alert-warning">
<p class="alert-title">⚠️ Alert!</p>
</blockquote>`,
	)
}

