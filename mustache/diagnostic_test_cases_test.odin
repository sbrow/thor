#+test
package mustache

import "core:testing"

@(test)
test_diag_missing_2nd_closing_brace :: proc(t: ^testing.T) {
	run_diag_case(t, "Missing 2nd closing brace")
}

@(test)
test_diag_missing_2nd_opening_brace :: proc(t: ^testing.T) {
	run_diag_case(t, "Missing 2nd opening brace")
}

@(test)
test_diag_mismatched_section_tags :: proc(t: ^testing.T) {
	run_diag_case(t, "Mismatched section tags")
}

@(test)
test_diag_missing_closing_section :: proc(t: ^testing.T) {
	run_diag_case(t, "Missing closing section")
}

@(test)
test_diag_empty_tag :: proc(t: ^testing.T) {
	run_diag_case(t, "empty tag")
}

@(test)
test_diag_empty_raw_tag :: proc(t: ^testing.T) {
	run_diag_case(t, "empty raw tag")
}

@(test)
test_diag_missing_pipe_arguement :: proc(t: ^testing.T) {
	run_diag_case(t, "Missing pipe arguement")
}

@(test)
test_diag_double_dot_access :: proc(t: ^testing.T) {
	run_diag_case(t, "Double dot access")
}

@(test)
test_diag_too_many_opening_braces :: proc(t: ^testing.T) {
	run_diag_case(t, "Too many opening braces")
}

@(test)
test_diag_too_many_closing_braces :: proc(t: ^testing.T) {
	run_diag_case(t, "Too many closing braces")
}

@(test)
test_diag_no_error_when_missing_index_page :: proc(t: ^testing.T) {
	run_diag_case(t, "No error when missing index page")
}

@(test)
test_diag_format_pipe_with_no_date_format_set :: proc(t: ^testing.T) {
	run_diag_case(t, "format pipe with no date format set")
}

@(test)
test_diag_first_last_with_zero_argument :: proc(t: ^testing.T) {
	run_diag_case(t, "first/last with zero argument")
}

@(test)
test_diag_first_last_with_negative_argument :: proc(t: ^testing.T) {
	run_diag_case(t, "first/last with negative argument")
}

@(test)
test_diag_first_succeeds_on_params_author_name :: proc(t: ^testing.T) {
	run_diag_case(t, "first succeeds on params.author.name")
}

@(test)
test_diag_first_last_in_partial :: proc(t: ^testing.T) {
	run_diag_case(t, "first/last in partial")
}

@(test)
test_diag_pipes_are_ignored_in_comments :: proc(t: ^testing.T) {
	run_diag_case(t, "Pipes are ignored in comments")
}

