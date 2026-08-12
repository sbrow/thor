#+feature dynamic-literals
#+test
package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:testing"
import "core:time/datetime"
import "core:time/timezone"

write_temp_config :: proc(name: string, content: string) -> string {
	path := fmt.tprintf("./test_thor_%s.json", name)
	write_err := os.write_entire_file_from_string(path, content)
	if write_err != nil {
		return ""
	}
	return path
}

@(test)
test_load_config_file :: proc(t: ^testing.T) {
	path := write_temp_config(
		"valid",
		`{
			"title":"Test Site",
			"description":"Test desc",
			"base_url":"https://example.com",
			"params":{
				"author":"Tester",
				"social":[
					{"name":"github","url":"https://github.com/test"},
					{"name":"rss","url":"/index.xml"}]
			}
		}`,
	)
	defer os.remove(path)

	cfg: Config_File
	ok := load_config_file(&cfg, path, context.temp_allocator)

	testing.expect(t, ok)
	testing.expect_value(t, cfg.title, "Test Site")
	testing.expect_value(t, cfg.description, "Test desc")
	testing.expect_value(t, cfg.base_url, "https://example.com")

	params, has_params := cfg.params.(json.Object)
	testing.expect(t, has_params)

	author_val := params["author"]
	author, has_author := author_val.(json.String)
	testing.expect(t, has_author)
	testing.expect_value(t, author, "Tester")

	social_val := params["social"]
	social, has_social := social_val.(json.Array)
	testing.expect(t, has_social)
	testing.expect_value(t, len(social), 2)

	link0, has_link0 := social[0].(json.Object)
	testing.expect(t, has_link0)
	testing.expect_value(t, link0["name"].(string), "github")
	testing.expect_value(t, link0["url"].(string), "https://github.com/test")

	link1, _ := social[1].(json.Object)
	testing.expect_value(t, link1["name"].(string), "rss")
	testing.expect_value(t, link1["url"].(string), "/index.xml")
}

@(test)
test_load_config_file_missing :: proc(t: ^testing.T) {
	cfg: Config_File
	ok := load_config_file(&cfg, "./nonexistent_thor_test.json", context.temp_allocator)
	testing.expect(t, !ok)
}

@(test)
test_load_config_file_invalid_json :: proc(t: ^testing.T) {
	path := write_temp_config("invalid", `{not valid json}`)
	defer os.remove(path)

	cfg: Config_File
	ok := false
	{
		ok = load_config_file(&cfg, path, context.temp_allocator)
	}
	testing.expect(t, !ok)
}

@(test)
test_load_config_file_partial :: proc(t: ^testing.T) {
	path := write_temp_config("partial", `{"title":"Partial"}`)
	defer os.remove(path)

	cfg: Config_File
	ok := load_config_file(&cfg, path, context.temp_allocator)

	testing.expect(t, ok)
	testing.expect_value(t, cfg.title, "Partial")
	testing.expect_value(t, cfg.description, "")
	testing.expect(t, cfg.params == nil)
}

@(test)
test_init_site_defaults_no_config :: proc(t: ^testing.T) {

	site: Site
	_flags: Flags
	flags.parse_or_exit(&_flags, []string{"thor", "-config:./nonexistent.json"}, .Odin)
	init_site(&site, _flags)
	defer destroy_site(&site)

	testing.expect_value(t, site.content_dir, "./content")
	testing.expect_value(t, site.assets_dir, "./assets")
	testing.expect_value(t, site.output_dir, "./public")
	testing.expect_value(t, site.layouts_dir, "./layouts")
	testing.expect_value(t, site.base_url, "http://localhost:8080")
	testing.expect(t, .Emoji in site.markdown_extensions)
	testing.expect(t, .Sidenotes in site.markdown_extensions)
	testing.expect(t, .Alerts in site.markdown_extensions)
}

@(test)
test_init_site_config_dir_relative :: proc(t: ^testing.T) {

	site: Site
	_flags: Flags
	flags.parse_or_exit(&_flags, []string{"thor", "-config:./sub/nonexistent.json"}, .Odin)
	init_site(&site, _flags)
	defer destroy_site(&site)

	testing.expect_value(t, site.content_dir, "./sub/content")
	testing.expect_value(t, site.assets_dir, "./sub/assets")
	testing.expect_value(t, site.output_dir, "./sub/public")
	testing.expect_value(t, site.layouts_dir, "./sub/layouts")
}

@(test)
test_init_site_flag_overrides_default :: proc(t: ^testing.T) {

	site: Site
	_flags: Flags
	flags.parse_or_exit(&_flags, []string{"thor", "-config:./nonexistent.json", "-drafts", "-base-url:https://flag.com"}, .Odin)
	init_site(&site, _flags)
	defer destroy_site(&site)

	testing.expect(t, .Drafts in site.features)
	testing.expect_value(t, site.base_url, "https://flag.com")
}

@(test)
test_init_site_full_pipeline :: proc(t: ^testing.T) {

	path := write_temp_config(
		"pipeline",
		`{"title":"Pipeline Test","description":"Full","base_url":"https://config.com"}`,
	)
	defer os.remove(path)

	site: Site
	_flags: Flags
	flags.parse_or_exit(&_flags, []string{"thor", fmt.tprintf("-config:%s", path), "-drafts"}, .Odin)
	init_site(&site, _flags)
	defer destroy_site(&site)

	testing.expect_value(t, site.title, "Pipeline Test")
	testing.expect_value(t, site.description, "Full")
	testing.expect(t, .Drafts in site.features)
	testing.expect_value(t, site.base_url, "https://config.com")
}

@(test)
test_init_site_md_enable_disable :: proc(t: ^testing.T) {

	site: Site
	_flags: Flags
	flags.parse_or_exit(&_flags, []string {
		"thor",
		"-config:./nonexistent.json",
		"-ext:highlight,sections",
		"-no-ext:emoji",
	}, .Odin)
	init_site(&site, _flags)
	defer destroy_site(&site)

	testing.expect(t, .Highlight in site.markdown_extensions)
	testing.expect(t, .Sections in site.markdown_extensions)
	testing.expect(t, !(.Emoji in site.markdown_extensions))
	testing.expect(t, .Sidenotes in site.markdown_extensions)
}

@(test)
test_init_site_config_paths :: proc(t: ^testing.T) {

	path := write_temp_config(
		"paths",
		`{
		"content_dir": "/custom/content",
		"assets_dir": "/custom/assets",
		"output_dir": "/custom/output",
		"layouts_dir": "/custom/layouts"
	}`,
	)
	defer os.remove(path)

	site: Site
	_flags: Flags
	flags.parse_or_exit(&_flags, []string{"thor", fmt.tprintf("-config:%s", path)}, .Odin)
	init_site(&site, _flags)
	defer destroy_site(&site)

	testing.expect_value(t, site.content_dir, "/custom/content")
	testing.expect_value(t, site.assets_dir, "/custom/assets")
	testing.expect_value(t, site.output_dir, "/custom/output")
	testing.expect_value(t, site.layouts_dir, "/custom/layouts")
}

// --- merge_params tests ---

@(test)
test_merge_params_both_present :: proc(t: ^testing.T) {
	site_params, _ := json.parse_string(
		`{"social": [], "author": "Tester"}`,
		spec = .JSON,
		allocator = context.temp_allocator,
	)
	page_params, _ := json.parse_string(
		`{"starred": true}`,
		spec = .JSON,
		allocator = context.temp_allocator,
	)

	merged_val := merge_params(site_params, page_params)
	merged, ok := merged_val.(json.Object)
	testing.expect(t, ok, "merged should be a json.Object")

	_, has_social := merged["social"]
	testing.expect(t, has_social, "site param 'social' should survive merge")

	_, has_author := merged["author"]
	testing.expect(t, has_author, "site param 'author' should survive merge")

	starred, has_starred := merged["starred"]
	testing.expect(t, has_starred, "page param 'starred' should be present")
	starred_bool, _ := starred.(json.Boolean)
	testing.expect(t, bool(starred_bool), "starred should be true")
}

@(test)
test_merge_params_nil_page :: proc(t: ^testing.T) {
	site_params, _ := json.parse_string(
		`{"author": "Tester"}`,
		spec = .JSON,
		allocator = context.temp_allocator,
	)

	merged_val := merge_params(site_params, nil)
	merged, ok := merged_val.(json.Object)
	testing.expect(t, ok, "should return site params when page is nil")

	_, has_author := merged["author"]
	testing.expect(t, has_author, "site param should survive")
}

@(test)
test_merge_params_nil_site :: proc(t: ^testing.T) {
	page_params, _ := json.parse_string(
		`{"starred": true}`,
		spec = .JSON,
		allocator = context.temp_allocator,
	)

	merged_val := merge_params(nil, page_params)
	merged, ok := merged_val.(json.Object)
	testing.expect(t, ok, "should return page params when site is nil")

	_, has_starred := merged["starred"]
	testing.expect(t, has_starred, "page param should survive")
}

@(test)
test_merge_params_both_nil :: proc(t: ^testing.T) {
	merged_val := merge_params(nil, nil)
	testing.expect(t, merged_val == nil, "both nil should return nil")
}

@(test)
test_merge_params_page_overrides_site :: proc(t: ^testing.T) {
	site_params, _ := json.parse_string(
		`{"key": "site_value"}`,
		spec = .JSON,
		allocator = context.temp_allocator,
	)
	page_params, _ := json.parse_string(
		`{"key": "page_value"}`,
		spec = .JSON,
		allocator = context.temp_allocator,
	)

	merged_val := merge_params(site_params, page_params)
	merged, ok := merged_val.(json.Object)
	testing.expect(t, ok)

	val := merged["key"]
	str, _ := val.(json.String)
	testing.expect_value(t, string(str), "page_value")
}

