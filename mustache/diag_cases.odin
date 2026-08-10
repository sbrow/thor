package mustache

import "core:os"
import "core:path/filepath"
import "core:strings"

Diag_Case :: struct {
	name:     string,
	enable:   bool,
	should:   string, // "error" | "warn" | "pass"
	expected: string, // exact formatted diagnostic output
	input:    string,
}

load_diag_cases :: proc(path: string, allocator := context.temp_allocator) -> []Diag_Case {
	dirs := [?]string{#directory, path}
	full_path, _ := filepath.join(dirs[:], allocator)
	raw_data, err := os.read_entire_file(full_path, allocator)
	if err != nil {
		return {}
	}

	content := string(raw_data)
	lines := strings.split(content, "\n", allocator)

	cases := make([dynamic]Diag_Case, 0, 16, allocator)

	current: Diag_Case
	has_current := false

	// Multiline block state
	in_block := false
	block_key: string
	block_indent := -1
	block_sb: strings.Builder

	for line in lines {
		raw := strings.trim_right(line, "\r")

		if in_block {
			// Check if this line belongs to the multiline block
			is_indented := len(raw) == 0 || raw[0] == ' ' || raw[0] == '\t'
			if is_indented {
				if block_indent < 0 && len(raw) > 0 {
					// Determine indentation from first content line
					block_indent = 0
					for block_indent < len(raw) && raw[block_indent] == ' ' {
						block_indent += 1
					}
				}
				// Strip block indentation
				stripped := raw
				if block_indent > 0 && len(stripped) >= block_indent {
					stripped = stripped[block_indent:]
				}
				if strings.builder_len(block_sb) > 0 {
					strings.write_string(&block_sb, "\n")
				}
				strings.write_string(&block_sb, stripped)
				continue
			} else {
				// End of multiline block
				in_block = false
				strings.write_string(&block_sb, "\n") // YAML | trailing newline
				value := strings.clone(strings.to_string(block_sb), allocator)
				strings.builder_destroy(&block_sb)
				set_field(&current, block_key, value)
				block_indent = -1
				// Fall through to process this line
			}
		}

		trimmed := strings.trim_space(raw)

		// Entry separator
		if trimmed == "---" {
			if has_current {
				append(&cases, current)
				current = {}
				has_current = false
			}
			continue
		}

		// Skip blank lines outside blocks
		if trimmed == "" {
			continue
		}

		// Multiline block start: "key: |"
		if strings.has_suffix(trimmed, ": |") {
			colon := strings.last_index(trimmed, ":")
			if colon > 0 {
				block_key = strings.trim_space(trimmed[:colon])
				strings.builder_init(&block_sb, allocator)
				in_block = true
				has_current = true
				continue
			}
		}

		// Simple key: value
		colon := strings.index(trimmed, ":")
		if colon > 0 {
			key := strings.trim_space(trimmed[:colon])
			value := strings.trim_space(trimmed[colon + 1:])
			// Strip matching outer quotes
			if len(value) >= 2 {
				if (value[0] == '"' && value[len(value) - 1] == '"') ||
				   (value[0] == '\'' && value[len(value) - 1] == '\'') {
					value = value[1:len(value) - 1]
				}
			}
			set_field(&current, key, value)
			has_current = true
		}
	}

	// Flush trailing multiline block
	if in_block {
		strings.write_string(&block_sb, "\n") // YAML | trailing newline
		value := strings.clone(strings.to_string(block_sb), allocator)
		strings.builder_destroy(&block_sb)
		set_field(&current, block_key, value)
	}

	// Flush last entry
	if has_current {
		append(&cases, current)
	}

	return cases[:]
}

set_field :: proc(c: ^Diag_Case, key, value: string) {
	switch key {
	case "name":
		c.name = value
	case "enable":
		c.enable = value == "true"
	case "should":
		c.should = value
	case "expected":
		c.expected = value
	case "input":
		c.input = value
	}
}

