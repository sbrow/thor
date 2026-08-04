#+test
package markdown

import "core:testing"

@(test)
test_basic_emoji_expansion_works :: proc(t: ^testing.T) {
	testing.expect_value(t, expand_emoji(":smile:"), "😄")
	testing.expect_value(t, expand_emoji(":smile: :heart:"), "😄 ❤️")
	testing.expect_value(t, expand_emoji(":smile::heart:"), "😄❤️")
	testing.expect_value(t, expand_emoji("Hello :wave:!"), "Hello 👋!")
	testing.expect_value(t, expand_emoji(":smile: rest"), "😄 rest")
	testing.expect_value(t, expand_emoji("rest :smile:"), "rest 😄")
	testing.expect_value(t, expand_emoji(":100:"), "💯")
	testing.expect_value(t, expand_emoji(":stuck_out_tongue:"), "😛")
}

@(test)
test_emoji_skips_non_matches :: proc(t: ^testing.T) {
	testing.expect_value(t, expand_emoji("Hello world"), "Hello world")
	testing.expect_value(t, expand_emoji("Hello:"), "Hello:")
	testing.expect_value(t, expand_emoji(":notreal:"), ":notreal:")
	testing.expect_value(t, expand_emoji("http://example.com"), "http://example.com")
	testing.expect_value(t, expand_emoji(""), "")
}

@(test)
test_emoji_skips_invalid_shortcodes :: proc(t: ^testing.T) {
	testing.expect_value(t, expand_emoji("::"), "::")
	testing.expect_value(t, expand_emoji(":Smile:"), ":Smile:")
	testing.expect_value(t, expand_emoji(": not real :"), ": not real :")
}

