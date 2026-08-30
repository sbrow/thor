package main

import "core:os"

// Path to the built-in default layouts, resolved at runtime.
//
// The default points at the `defaults` directory next to the source tree (via
// `#directory`), which works for local `odin run`/`odin build` from the repo.
// Packaged builds install `defaults/` to a fixed location and override this
// with `-define:THOR_DEFAULTS_PATH=<path>` (see flake.nix).
//
// TODO: bake these into the binary at compile time via `#load_directory` so the
// binary is self-contained and this runtime path goes away entirely. See
// TODOS.md.
DEFAULTS_PATH :: #config(
	THOR_DEFAULTS_PATH,
	#directory + os.Path_Separator_String + "defaults",
)
