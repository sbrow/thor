#+test
package mustache

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// tool_test_dirs makes a fresh in/out dir pair under the system temp dir and
// returns their paths (unique per name).
tool_test_dirs :: proc(name: string) -> (in_dir, out_dir: string) {
	base, _ := os.temp_directory(context.temp_allocator)
	in_dir = fmt.tprintf("%s/thor_tool_test/%s/in", base, name)
	out_dir = fmt.tprintf("%s/thor_tool_test/%s/out", base, name)
	os.make_directory_all(in_dir)
	os.make_directory_all(out_dir)
	return
}

// Tool_Test_Ctx carries the asset path as a context value (mustache resolves
// tag keys from the context, not from quoted literals).
Tool_Test_Ctx :: struct {
	p: string,
}

@(test)
test_tool_unknown_tool :: proc(t: ^testing.T) {
	reg: Tool_Registry // no commands configured
	tpl, _ := parse(`{{ p | tool nope }}`)
	defer delete_template(&tpl)
	_, err := render(tpl, Tool_Test_Ctx{p = "/a.css"}, tools = &reg)
	testing.expect(t, err != nil, "unknown tool should be a hard error")
}

@(test)
test_tool_unavailable_without_registry :: proc(t: ^testing.T) {
	// No registry threaded through (tools == nil): the pipe must fail rather
	// than silently do nothing.
	tpl, _ := parse(`{{ p | tool anything }}`)
	defer delete_template(&tpl)
	_, err := render(tpl, Tool_Test_Ctx{p = "/a.css"})
	testing.expect(t, err != nil, "tool pipe without a registry should error")
}

@(test)
test_tool_arg_count :: proc(t: ^testing.T) {
	reg: Tool_Registry

	// Zero args.
	tpl0, _ := parse(`{{ p | tool }}`)
	defer delete_template(&tpl0)
	_, err0 := render(tpl0, Tool_Test_Ctx{p = "/a.css"}, tools = &reg)
	testing.expect(t, err0 != nil, "tool with no name should error")

	// Two args.
	tpl2, _ := parse(`{{ p | tool one two }}`)
	defer delete_template(&tpl2)
	_, err2 := render(tpl2, Tool_Test_Ctx{p = "/a.css"}, tools = &reg)
	testing.expect(t, err2 != nil, "tool with two args should error")
}

@(test)
test_tool_absolute_url_passthrough :: proc(t: ^testing.T) {
	// A CDN URL has no local source; it should pass through untouched.
	reg: Tool_Registry
	url, err := run_tool(&reg, "anything", "https://cdn.example.com/x.css", 0)
	testing.expect(t, err == nil, "absolute URL should not error")
	testing.expect_value(t, url, "https://cdn.example.com/x.css")
}

@(test)
test_tool_source_not_found :: proc(t: ^testing.T) {
	in_dir, out_dir := tool_test_dirs("missing_src")
	commands := make(map[string]string, context.temp_allocator)
	commands["cp"] = "cp {{in}} {{out}}"
	reg := Tool_Registry {
		commands   = commands,
		input_dir  = in_dir,
		output_dir = out_dir,
	}

	_, err := run_tool(&reg, "cp", "/nope.css", 0)
	testing.expect(t, err != nil, "missing source file should be a hard error")
}

@(test)
test_tool_missing_binary :: proc(t: ^testing.T) {
	in_dir, out_dir := tool_test_dirs("missing_bin")
	_ = os.write_entire_file_from_string(fmt.tprintf("%s/a.css", in_dir), "body{}")

	commands := make(map[string]string, context.temp_allocator)
	commands["ghost"] = "thor-tool-does-not-exist-xyz {{in}} {{out}}"
	reg := Tool_Registry {
		commands   = commands,
		input_dir  = in_dir,
		output_dir = out_dir,
	}

	_, err := run_tool(&reg, "ghost", "/a.css", 0)
	testing.expect(t, err != nil, "missing binary should be caught by PATH check")
}

@(test)
test_tool_runs :: proc(t: ^testing.T) {
	when ODIN_OS != .Windows {
		in_dir, out_dir := tool_test_dirs("runs")
		os.make_directory_all(fmt.tprintf("%s/css", in_dir))
		_ = os.write_entire_file_from_string(
			fmt.tprintf("%s/css/main.css", in_dir),
			"body { color: red }",
		)

		commands := make(map[string]string, context.temp_allocator)
		commands["copyit"] = "cp {{in}} {{out}}"
		reg := Tool_Registry {
			commands   = commands,
			input_dir  = in_dir,
			output_dir = out_dir,
		}

		tpl, _ := parse(`{{ p | tool copyit }}`)
		defer delete_template(&tpl)
		result, err := render(tpl, Tool_Test_Ctx{p = "/css/main.css"}, tools = &reg)
		defer delete(result)
		testing.expect(t, err == nil, "cp tool should succeed")
		testing.expect_value(t, result, "/css/main.css")

		// The tool wrote the output file.
		written := fmt.tprintf("%s/css/main.css", out_dir)
		data, rerr := os.read_entire_file_from_path(written, context.temp_allocator)
		testing.expect(t, rerr == nil, "output file should exist")
		testing.expect_value(t, string(data), "body { color: red }")

		// The result was memoized; a second call for the same asset returns the
		// same URL from the registry (mutated through the pointer).
		url2, err2 := run_tool(&reg, "copyit", "/css/main.css", 0)
		testing.expect(t, err2 == nil, "memoized call should not error")
		testing.expect_value(t, url2, "/css/main.css")
		testing.expect(t, len(reg.manifest) == 1, "result should be memoized")
	}
}

// tool_io_case runs `cmd` over a source file containing `content` and returns
// the resulting output-file contents. Exercises the in/out ↔ stdin/stdout 2×2.
tool_io_case :: proc(name, cmd, content: string) -> (out: string, ok: bool) {
	in_dir, out_dir := tool_test_dirs(name)
	_ = os.write_entire_file_from_string(fmt.tprintf("%s/a.css", in_dir), content)
	commands := make(map[string]string, context.temp_allocator)
	commands[name] = cmd
	reg := Tool_Registry {
		commands   = commands,
		input_dir  = in_dir,
		output_dir = out_dir,
	}
	_, err := run_tool(&reg, name, "/a.css", 0)
	if err != nil {
		return "", false
	}
	data, rerr := os.read_entire_file_from_path(
		fmt.tprintf("%s/a.css", out_dir),
		context.temp_allocator,
	)
	return string(data), rerr == nil
}

@(test)
test_tool_stdin_stdout :: proc(t: ^testing.T) {
	when ODIN_OS != .Windows {
		// `cat` with no args: reads stdin (thor feeds the source), writes stdout
		// (thor captures and persists it).
		out, ok := tool_io_case("stream", "cat", "body{a:1}")
		testing.expect(t, ok, "cat (stdin→stdout) should produce output")
		testing.expect_value(t, out, "body{a:1}")
	}
}

@(test)
test_tool_in_path_stdout :: proc(t: ^testing.T) {
	when ODIN_OS != .Windows {
		// `cat {{in}}`: tool opens the file by path, streams to stdout.
		out, ok := tool_io_case("in_stream", "cat {{in}}", "body{b:2}")
		testing.expect(t, ok, "cat {{in}} (file→stdout) should produce output")
		testing.expect_value(t, out, "body{b:2}")
	}
}

@(test)
test_tool_stdin_out_path :: proc(t: ^testing.T) {
	when ODIN_OS != .Windows {
		// `tee {{out}}`: thor feeds stdin, tool writes the file itself.
		out, ok := tool_io_case("stream_out", "tee {{out}}", "body{c:3}")
		testing.expect(t, ok, "tee {{out}} (stdin→file) should produce output")
		testing.expect_value(t, out, "body{c:3}")
	}
}

@(test)
test_tool_minify_section :: proc(t: ^testing.T) {
	// The command template is itself mustache: {{#minify}} should expand only
	// when the registry has minify on. Verify via the rendered command string.
	cmd, err := render_command("prog {{#minify}}--min{{/minify}} {{in}}", "/a", "/b", true, 0)
	testing.expect(t, err == nil, "render_command should succeed (minify on)")
	testing.expect(t, strings.contains(cmd, "--min"), "minify section should render when on")

	cmd2, err2 := render_command("prog {{#minify}}--min{{/minify}} {{in}}", "/a", "/b", false, 0)
	testing.expect(t, err2 == nil, "render_command should succeed (minify off)")
	testing.expect(t, !strings.contains(cmd2, "--min"), "minify section should be empty when off")
}
