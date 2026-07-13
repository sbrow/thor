#+feature dynamic-literals
#+test
package main

import "core:encoding/json"
import "core:fmt"
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
test_load_site_config :: proc(t: ^testing.T) {
	path := write_temp_config(
		"valid",
		`{
			"title":"Test Site",
			"description":"Test desc",
			"base_url":"https://example.com",
			"author":"Tester",
			"params":{
				"social":[
					{"name":"github","url":"https://github.com/test"},
					{"name":"rss","url":"/index.xml"}]
			}
		}`,
	)
	defer os.remove(path)

	site: Site
	ok := load_site_config(&site, path, context.temp_allocator)

	testing.expect(t, ok)
	testing.expect_value(t, site.title, "Test Site")
	testing.expect_value(t, site.description, "Test desc")
	testing.expect_value(t, site.base_url, "https://example.com")
	testing.expect_value(t, site.author, "Tester")

	params, has_params := site.params.(json.Object)
	testing.expect(t, has_params)

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
test_load_site_config_missing_file :: proc(t: ^testing.T) {
	site: Site
	ok := load_site_config(&site, "./nonexistent_thor_test.json", context.temp_allocator)
	testing.expect(t, !ok)
}

@(test)
test_load_site_config_invalid_json :: proc(t: ^testing.T) {
	path := write_temp_config("invalid", `{not valid json}`)
	defer os.remove(path)

	site: Site
	ok := load_site_config(&site, path, context.temp_allocator)
	testing.expect(t, !ok)
}

@(test)
test_load_site_config_partial :: proc(t: ^testing.T) {
	path := write_temp_config("partial", `{"title":"Partial"}`)
	defer os.remove(path)

	site: Site
	ok := load_site_config(&site, path, context.temp_allocator)

	testing.expect(t, ok)
	testing.expect_value(t, site.title, "Partial")
	testing.expect_value(t, site.description, "")
	testing.expect_value(t, site.author, "")
	testing.expect(t, site.params == nil)
}

@(test)
test_site_merge_overrides :: proc(t: ^testing.T) {
	config := Site {
		base_url    = "https://original.com",
		content_dir = "./content",
	}
	flags := Site {
		base_url = "https://override.com",
	}

	site_merge(&config, flags)

	testing.expect_value(t, config.base_url, "https://override.com")
	testing.expect_value(t, config.content_dir, "./content")
}

@(test)
test_site_merge_empty_flags_keep_config :: proc(t: ^testing.T) {
	config := Site {
		base_url    = "https://keep.com",
		content_dir = "./keep",
	}
	flags := Site{}

	site_merge(&config, flags)

	testing.expect_value(t, config.base_url, "https://keep.com")
	testing.expect_value(t, config.content_dir, "./keep")
}

@(test)
test_site_merge_drafts_true :: proc(t: ^testing.T) {
	config := Site {
		drafts = false,
	}
	flags := Site {
		drafts = true,
	}

	site_merge(&config, flags)
	testing.expect(t, config.drafts)
}

@(test)
test_site_merge_drafts_false_preserves :: proc(t: ^testing.T) {
	config := Site {
		drafts = false,
	}
	flags := Site {
		drafts = false,
	}

	site_merge(&config, flags)
	testing.expect(t, !config.drafts)
}

@(test)
test_site_merge_config_path :: proc(t: ^testing.T) {
	config := Site{}
	flags := Site {
		config_path = "./custom/thor.json",
	}

	site_merge(&config, flags)
	testing.expect_value(t, config.config_path, "./custom/thor.json")
}

@(test)
test_init_site_defaults_no_config :: proc(t: ^testing.T) {
	site: Site
	args := []string{"thor", "-config:./nonexistent.json"}
	init_site(&site, args)
	defer destroy_site(&site)

	testing.expect_value(t, site.content_dir, "./content")
	testing.expect_value(t, site.output_dir, "./public")
	testing.expect_value(t, site.layouts_dir, "./layouts")
	testing.expect_value(t, site.base_url, "http://localhost:8080")
}

@(test)
test_init_site_config_dir_relative :: proc(t: ^testing.T) {
	site: Site
	args := []string{"thor", "-config:./sub/nonexistent.json"}
	init_site(&site, args)
	defer destroy_site(&site)

	testing.expect_value(t, site.content_dir, "./sub/content")
	testing.expect_value(t, site.output_dir, "./sub/public")
	testing.expect_value(t, site.layouts_dir, "./sub/layouts")
}

@(test)
test_init_site_flag_overrides_default :: proc(t: ^testing.T) {
	site: Site
	args := []string{"thor", "-config:./nonexistent.json", "-drafts", "-base-url:https://flag.com"}
	init_site(&site, args)
	defer destroy_site(&site)

	testing.expect(t, site.drafts)
	testing.expect_value(t, site.base_url, "https://flag.com")
}

@(test)
test_init_site_full_pipeline :: proc(t: ^testing.T) {
	path := write_temp_config(
		"pipeline",
		`{"title":"Pipeline Test","description":"Full","base_url":"https://config.com","author":"Author"}`,
	)
	defer os.remove(path)

	site: Site
	args := []string{"thor", fmt.tprintf("-config:%s", path), "-drafts"}
	init_site(&site, args)
	defer destroy_site(&site)

	testing.expect_value(t, site.title, "Pipeline Test")
	testing.expect_value(t, site.description, "Full")
	testing.expect_value(t, site.author, "Author")
	testing.expect(t, site.drafts)
	testing.expect_value(t, site.base_url, "https://config.com")
}

