package mustache

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

load_partials :: proc(
	dir: string,
	base: string = "",
	allocator := context.allocator,
) -> map[string]Template {
	partials := make(map[string]Template, allocator)

	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		log.warnf("cannot read partials dir %s: %v", dir, err)
		return partials
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)

	for entry in entries {
		if entry.type == .Regular {
			if !strings.has_suffix(entry.name, ".html") do continue
			stripped := entry.name[:len(entry.name) - len(".html")]
			key := fmt.tprintf("%s%s", base, stripped)
			data, ferr := os.read_entire_file_from_path(entry.fullpath, allocator)
			if ferr != nil do continue
			source := string(data)
			path := strings.clone(entry.fullpath, allocator)
			tmpl, perr := parse(source, path, allocator = allocator)
			if perr != nil {
				b := body(perr)
				log.warnf("failed to parse partial %s: %s", entry.fullpath, b.msg)
				continue
			}
			partials[key] = tmpl
		} else if entry.type == .Directory {
			sub_base := fmt.tprintf("%s%s/", base, entry.name)
			sub := load_partials(entry.fullpath, sub_base, allocator)
			for k, v in sub {
				partials[k] = v
			}
		}
	}

	return partials
}
