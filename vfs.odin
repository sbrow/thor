package main

import "core:fmt"
import "core:os"

// Virtual File System Entry
VFS_Entry :: struct {
	fs_path: string,
	data:    []byte,
}

// Virtual File System
VFS :: struct {
	files: map[string]VFS_Entry,
}

build_vfs :: proc(site: ^Site) {
	site.vfs.files = make(map[string]VFS_Entry, site_allocator(site))

	mount_dir(&site.vfs, fmt.tprintf("%s/layouts", DEFAULTS_PATH), "layouts")

	for i := len(site.modules) - 1; i >= 0; i -= 1 {
		module := site.modules[i]
		mount_subdir(&site.vfs, module, "layouts")
		mount_subdir(&site.vfs, module, "assets")
	}

	mount_dir(&site.vfs, site.layouts_dir, "layouts")
	mount_dir(&site.vfs, site.assets_dir, "assets")
}

mount_subdir :: proc(vfs: ^VFS, module_dir: string, target: string) {
	source := fmt.tprintf("%s/%s", module_dir, target)
	mount_dir(vfs, source, target)
}

mount_dir :: proc(vfs: ^VFS, source_dir: string, target: string) {
	if !os.exists(source_dir) {
		return
	}
	mount_recursive(vfs, source_dir, target)
}

mount_recursive :: proc(vfs: ^VFS, current_dir: string, target_prefix: string) {
	entries, err := os.read_all_directory_by_path(current_dir, context.allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		#partial switch entry.type {
		case .Regular:
			virtual := fmt.tprintf("%s/%s", target_prefix, entry.name)
			vfs.files[virtual] = VFS_Entry {
				fs_path = entry.fullpath,
			}
		case .Directory:
			sub_prefix := fmt.tprintf("%s/%s", target_prefix, entry.name)
			mount_recursive(vfs, entry.fullpath, sub_prefix)
		case:
		}
	}
}

vfs_get :: proc(vfs: ^VFS, virtual_path: string) -> ([]byte, bool) {
	entry, ok := vfs.files[virtual_path]
	if !ok {
		return nil, false
	}
	if entry.data != nil {
		return entry.data, true
	}
	data, err := os.read_entire_file_from_path(entry.fs_path, context.allocator)
	if err != nil {
		return nil, false
	}
	return data, true
}

// vfs_get_entry returns both the VFS_Entry (for fs_path) and the lazily-loaded
// data. Use this instead of vfs_get when you need the entry's metadata along
// with the contents.
vfs_get_entry :: proc(vfs: ^VFS, virtual_path: string) -> (VFS_Entry, []byte, bool) {
	entry, ok := vfs.files[virtual_path]
	if !ok {
		return {}, nil, false
	}
	if entry.data != nil {
		return entry, entry.data, true
	}
	data, err := os.read_entire_file_from_path(entry.fs_path, context.allocator)
	if err != nil {
		return entry, nil, false
	}
	return entry, data, true
}

// vfs_entry_data returns the data for a VFS_Entry, reading from disk if it
// hasn't been loaded yet. Useful when iterating vfs.files directly (where you
// already have the entry and don't want a redundant map lookup).
vfs_entry_data :: proc(entry: VFS_Entry) -> ([]byte, bool) {
	if entry.data != nil {
		return entry.data, true
	}
	data, err := os.read_entire_file_from_path(entry.fs_path, context.allocator)
	if err != nil {
		return nil, false
	}
	return data, true
}

