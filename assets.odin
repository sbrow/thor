package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

import ts "treesitter"

copy_assets_dir :: proc(vfs: ^VFS, output_dir: string, features: bit_set[Feature]) {
	// One CSS parser, reused for every .css asset (single-threaded). Owned here.
	css_parser: ts.Parser
	if .Minify in features {
		if g, ok := ts.grammar("css"); ok {
			css_parser = ts.open_parser(g)
		}
	}
	defer if css_parser != nil {
		ts.parser_delete(css_parser)
	}

	for virtual_path, entry in vfs.files {
		if !strings.has_prefix(virtual_path, "assets/") {
			continue
		}

		rel := virtual_path[len("assets/"):]
		dest := fmt.tprintf("%s/%s", output_dir, rel)

		if idx := strings.last_index(dest, "/"); idx >= 0 {
			if err := os.make_directory_all(dest[:idx]); err != nil && err != .Exist {
				log.warnf("cannot create %s: %v", dest[:idx], err)
				continue
			}
		}

		if .Minify in features && strings.has_suffix(rel, ".css") {
			data, ok := vfs_get(vfs, virtual_path)
			if ok {
				if m, mok := minify_css(css_parser, string(data)); mok {
					write_file(dest, m)
				} else {
					write_file(dest, string(data))
				}
			}
		} else if entry.data != nil {
			if err := os.write_entire_file(dest, entry.data); err != nil {
				log.warnf("cannot write %s: %v", dest, err)
			}
		} else {
			if err := os.copy_file(dest, entry.fs_path); err != nil {
				log.warnf("cannot copy %s: %v", entry.fs_path, err)
			}
		}
	}
}
