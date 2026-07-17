package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

// copy_assets_dir recursively copies files from assets_dir to output_dir.
// .css files are minified when .Minify is enabled; all other files are copied verbatim.
// Silently skips if assets_dir doesn't exist.
copy_assets_dir :: proc(assets_dir: string, output_dir: string, features: bit_set[Feature]) {
	if !os.exists(assets_dir) {
		return
	}
	copy_assets_recursive(assets_dir, "", output_dir, features)
}

copy_assets_recursive :: proc(
	current: string,
	rel_prefix: string,
	output_dir: string,
	features: bit_set[Feature],
) {
	entries, err := os.read_all_directory_by_path(current, context.allocator)
	if err != nil {
		log.warnf("thor: cannot read %s: %v", current, err)
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		rel := rel_prefix == "" ? entry.name : fmt.tprintf("%s/%s", rel_prefix, entry.name)
		switch entry.type {
		case .Regular:
			dest := fmt.tprintf("%s/%s", output_dir, rel)
			if idx := strings.last_index(dest, "/"); idx >= 0 {
				if err := os.make_directory_all(dest[:idx]); err != nil && err != .Exist {
					log.warnf("thor: cannot create %s: %v", dest[:idx], err)
					continue
				}
			}
			if .Minify in features && strings.has_suffix(entry.name, ".css") {
				data, read_err := os.read_entire_file_from_path(entry.fullpath, context.allocator)
				if read_err != nil {
					log.warnf("thor: cannot read %s: %v", entry.fullpath, read_err)
					continue
				}
				minified := minify_css(string(data))
				write_file(dest, minified)
			} else {
				if err := os.copy_file(dest, entry.fullpath); err != nil {
					log.warnf("thor: cannot copy %s: %v", entry.fullpath, err)
				}
			}
		case .Directory:
			copy_assets_recursive(entry.fullpath, rel, output_dir, features)
		case .Undetermined, .Symlink, .Named_Pipe, .Socket, .Block_Device, .Character_Device:
		}
	}
}

