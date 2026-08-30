#+test
package mustache

import "core:testing"

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

