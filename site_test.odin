#+feature dynamic-literals
#+test
package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:testing"

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
		context.logger = log.nil_logger()
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
	args := []string{"thor", "-config:./nonexistent.json"}
	init_site(&site, args)
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
	args := []string{"thor", "-config:./sub/nonexistent.json"}
	init_site(&site, args)
	defer destroy_site(&site)

	testing.expect_value(t, site.content_dir, "./sub/content")
	testing.expect_value(t, site.assets_dir, "./sub/assets")
	testing.expect_value(t, site.output_dir, "./sub/public")
	testing.expect_value(t, site.layouts_dir, "./sub/layouts")
}

@(test)
test_init_site_flag_overrides_default :: proc(t: ^testing.T) {
	site: Site
	args := []string{"thor", "-config:./nonexistent.json", "-drafts", "-base-url:https://flag.com"}
	init_site(&site, args)
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
	args := []string{"thor", fmt.tprintf("-config:%s", path), "-drafts"}
	init_site(&site, args)
	defer destroy_site(&site)

	testing.expect_value(t, site.title, "Pipeline Test")
	testing.expect_value(t, site.description, "Full")
	testing.expect(t, .Drafts in site.features)
	testing.expect_value(t, site.base_url, "https://config.com")
}

@(test)
test_init_site_md_enable_disable :: proc(t: ^testing.T) {
	site: Site
	args := []string {
		"thor",
		"-config:./nonexistent.json",
		"-ext:highlight,sections",
		"-no-ext:emoji",
	}
	init_site(&site, args)
	defer destroy_site(&site)

	testing.expect(t, .Highlight in site.markdown_extensions)
	testing.expect(t, .Sections in site.markdown_extensions)
	testing.expect(t, !(.Emoji in site.markdown_extensions))
	testing.expect(t, .Sidenotes in site.markdown_extensions)
}

