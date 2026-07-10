#+test
package main

import "core:testing"

@(test)
test_true :: proc(t: ^testing.T) {
	testing.expect(t, true)
}

