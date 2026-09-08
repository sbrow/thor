package mustache

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"

// The `tool` pipe runs a user-configured external program over a site asset.
// A tool is a command string that is itself a mustache template; rendering it
// yields the command line, which is tokenized into argv and run via
// os.process_exec (no shell). The command template has three variables:
//
//   {{in}}      absolute path to the source file the tool should read
//   {{out}}     absolute path the tool should write its result to
//   {{#minify}} section, non-empty when the site is building with minify on
//
// The tool does its own file I/O through {{in}}/{{out}}; neither mustache nor
// the host shuffles bytes. The pipe takes an asset path (e.g. "/css/main.css"),
// runs the tool, and returns the root-relative URL of the written output.

// Tool_Registry is the host-supplied configuration for the `tool` pipe. The
// host (thor) owns one per build and threads a pointer to it through render, so
// it never enters the template context stack and can't be resolved as a key.
// The config fields are written once before rendering and only read thereafter;
// `manifest` is the sole mutable state and is guarded by `mu` — needed because
// render may go parallel and because os.process_start is not thread-safe.
Tool_Registry :: struct {
	commands:   map[string]string, // tool name -> command template
	input_dir:  string, // base dir for resolving {{in}} (the assets dir)
	output_dir: string, // base dir for the written output (the output dir)
	minify:     bool,
	manifest:   map[string]string, // (name\x00input) -> output URL, per build
	mu:         sync.Mutex,
}

// tool_registry_init prepares `reg` for one build: the input/output base dirs,
// the minify flag, and a fresh (empty) manifest. `commands` is configured
// separately (from thor.json) and left untouched. The manifest is temp-allocated
// — build-scoped, discarded when the build's temp allocator is reset. Nothing
// needs to be cleaned up between builds: the host recreates the whole registry.
tool_registry_init :: proc(reg: ^Tool_Registry, input_dir, output_dir: string, minify: bool) {
	reg.input_dir = input_dir
	reg.output_dir = output_dir
	reg.minify = minify
	reg.manifest = make(map[string]string, context.temp_allocator)
}

// run_tool executes the named tool over `input` (an asset path) and returns the
// root-relative URL of the produced file. Any failure is a hard error (.Data).
run_tool :: proc(
	reg: ^Tool_Registry,
	name: string,
	input: string,
	pos: int,
) -> (
	url: string,
	err: Error,
) {
	if reg == nil {
		return "", Error_Body{msg = "tool pipe is not available here", pos = pos, kind = .Data}
	}

	// Absolute URLs (CDN links, protocol-relative) have no local source; pass
	// them through so a mixed stylesheet list stays safe.
	if is_absolute_url(input) {
		return input, nil
	}

	cmd_tmpl, ok := reg.commands[name]
	if !ok {
		return "", Error_Body {
			msg = fmt.tprintf("unknown tool '%s' (add it to thor.json \"tools\")", name),
			pos = pos,
			kind = .Data,
		}
	}

	// Logical path -> in/out/url. Strip a single leading '/'.
	rel := input
	if len(rel) > 0 && rel[0] == '/' {
		rel = rel[1:]
	}
	if rel == "" {
		return "", Error_Body{msg = "tool: empty asset path", pos = pos, kind = .Data}
	}
	in_path := fmt.tprintf("%s/%s", reg.input_dir, rel)
	out_path := fmt.tprintf("%s/%s", reg.output_dir, rel)
	out_url := fmt.tprintf("/%s", rel)

	if !os.exists(in_path) {
		return "", Error_Body {
			msg = fmt.tprintf("tool '%s': source file not found: %s", name, in_path),
			pos = pos,
			kind = .Data,
		}
	}

	// Render the command template. Done OUTSIDE the lock so a command template
	// that (mistakenly) uses a `tool` pipe can't deadlock on reg.mu. The
	// registry fields it reads are immutable during rendering.
	cmd_str, rerr := render_command(cmd_tmpl, in_path, out_path, reg.minify, pos)
	if rerr != nil {
		return "", rerr
	}

	argv := tokenize_command(cmd_str, context.temp_allocator)
	if len(argv) == 0 {
		return "", Error_Body {
			msg = fmt.tprintf("tool '%s': command is empty", name),
			pos = pos,
			kind = .Data,
		}
	}
	if !find_on_path(argv[0]) {
		return "", Error_Body {
			msg = fmt.tprintf("tool '%s': program '%s' not found on PATH", name, argv[0]),
			pos = pos,
			kind = .Data,
		}
	}

	sync.lock(&reg.mu)
	defer sync.unlock(&reg.mu)

	key := fmt.tprintf("%s\x00%s", name, input)
	if cached, hit := reg.manifest[key]; hit {
		return cached, nil
	}

	// Ensure the output's parent dir exists so the tool can write {{out}}.
	if idx := strings.last_index(out_path, "/"); idx >= 0 {
		if merr := os.make_directory_all(out_path[:idx]); merr != nil && merr != .Exist {
			return "", Error_Body {
				msg = fmt.tprintf("tool '%s': cannot create %s: %v", name, out_path[:idx], merr),
				pos = pos,
				kind = .Data,
			}
		}
	}

	state, _, stderr, xerr := os.process_exec(
		os.Process_Desc{command = argv},
		context.temp_allocator,
	)
	if xerr != nil {
		return "", Error_Body {
			msg = fmt.tprintf("tool '%s': failed to run '%s': %v", name, argv[0], xerr),
			pos = pos,
			kind = .Data,
		}
	}
	if state.exit_code != 0 {
		return "", Error_Body {
			msg = fmt.tprintf(
				"tool '%s': '%s' exited %d\n%s",
				name,
				argv[0],
				state.exit_code,
				strings.trim_space(string(stderr)),
			),
			pos = pos,
			kind = .Data,
		}
	}

	// Memoize for the rest of this build. `key` and `out_url` are already on the
	// temp allocator — the same build-scoped lifetime as the manifest — so they
	// are stored directly, no clone needed.
	if reg.manifest == nil {
		reg.manifest = make(map[string]string, context.temp_allocator)
	}
	reg.manifest[key] = out_url
	return out_url, nil
}

// render_command renders a tool's command template with the in/out/minify
// context. Paths render through mustache's default HTML escaping; the paths we
// generate are controlled and contain no HTML-special characters, so this is
// harmless in practice.
render_command :: proc(
	tmpl_src, in_path, out_path: string,
	minify: bool,
	pos: int,
) -> (
	string,
	Error,
) {
	tmpl, perr := parse(tmpl_src, "", context.temp_allocator, context.temp_allocator)
	if perr != nil {
		b := body(perr)
		return "", Error_Body {
			msg = fmt.tprintf("invalid tool command template: %s", b.msg),
			pos = pos,
			kind = .Data,
		}
	}
	// `in`/`out` are Odin keywords, so the context is a map rather than a struct.
	data := make(map[string]any, 3, context.temp_allocator)
	data["in"] = in_path
	data["out"] = out_path
	data["minify"] = minify
	out, rerr := render(tmpl, data, allocator = context.temp_allocator)
	if rerr != nil {
		b := body(rerr)
		return "", Error_Body {
			msg = fmt.tprintf("failed to render tool command: %s", b.msg),
			pos = pos,
			kind = .Data,
		}
	}
	return out, nil
}

// is_absolute_url reports whether a path points outside the local site.
is_absolute_url :: proc(s: string) -> bool {
	return(
		strings.has_prefix(s, "http://") ||
		strings.has_prefix(s, "https://") ||
		strings.has_prefix(s, "//") \
	)
}

// tokenize_command splits a command line into argv on whitespace, treating a
// double-quoted span as a single token with the quotes stripped. No escape
// sequences or single quotes (kept deliberately minimal — commands come from a
// trusted config, not untrusted input).
tokenize_command :: proc(cmd: string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, 0, 8, allocator)
	i := 0
	for i < len(cmd) {
		for i < len(cmd) && is_pipe_space(cmd[i]) {
			i += 1
		}
		if i >= len(cmd) {
			break
		}
		if cmd[i] == '"' {
			j := i + 1
			for j < len(cmd) && cmd[j] != '"' {
				j += 1
			}
			append(&out, strings.clone(cmd[i + 1:j], allocator))
			i = j + 1 if j < len(cmd) else j
		} else {
			start := i
			for i < len(cmd) && !is_pipe_space(cmd[i]) {
				i += 1
			}
			append(&out, strings.clone(cmd[start:i], allocator))
		}
	}
	return out[:]
}

// find_on_path reports whether `prog` is executable: an explicit path is checked
// directly, otherwise each PATH entry is probed.
find_on_path :: proc(prog: string) -> bool {
	if strings.contains(prog, "/") {
		return os.exists(prog)
	}
	path := os.get_env_alloc("PATH", context.temp_allocator)
	if path == "" {
		return false
	}
	sep := ";" when ODIN_OS == .Windows else ":"
	for dir in strings.split_iterator(&path, sep) {
		if dir == "" {
			continue
		}
		candidate := fmt.tprintf("%s/%s", dir, prog)
		if os.exists(candidate) {
			return true
		}
	}
	return false
}
