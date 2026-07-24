# Tree-sitter Grammar Discovery

## Problem

Grammar (`.so`) and query (`.scm`) paths are hardcoded to the developer's machine:

```odin
GRAPHS_PATH: string = "/home/spencer/.config/helix/runtime/grammars"
QUERIES_PATH: string = "/nix/store/n9da8d...-helix-25.07.1/lib/runtime/queries"
```

Only works on one machine. CI and other users get no syntax highlighting.

## Design

### Config

`thor.json` gets two optional directory paths:

```json
{
  "grammar_dir": "~/.local/share/thor/grammars",
  "queries_dir": "~/.local/share/thor/queries"
}
```

These are thor's managed cache directories. Thor looks here first, and hardlinks discovered files into them.

### Discovery flow (per language, lazy)

When a code block with language X is encountered:

1. **Check configured dir**: `grammar_dir/X.so` — if exists, use it
2. **Search standard locations** (if not in configured dir):
   - `$HELIX_RUNTIME/grammars/X.so`
   - `~/.config/helix/runtime/grammars/X.so`
   - `~/.local/share/nvim/site/parser/X.so`
   - `/usr/lib/tree-sitter/X.so`
   - `/usr/local/lib/X.so`
3. **Hardlink** found file into `grammar_dir/X.so`
4. **Cache** in `grammar_cache` (in-memory, per-run)

Same flow for queries: `queries_dir/X/highlights.scm`, searching:
- `$HELIX_RUNTIME/queries/X/highlights.scm`
- `~/.config/helix/runtime/queries/X/highlights.scm`

### Subsequent runs

`grammar_dir/X.so` exists → skip search entirely. Fast cold start.

### Staleness

- User deletes file from `grammar_dir` → re-search on next run
- Source file changes (Helix update) → hardlink still points to old inode until source is deleted (Nix GC) or user manually clears
- Hardlink fails (cross-filesystem) → fall back to copy or symlink (TBD)

### HTML/CSS

Already statically linked via `mkGrammarStaticLib` in the flake. No change needed — `builtin_language()` handles them before the search path logic.

## Open questions

1. **Default location**: `~/.local/share/thor/grammars` (XDG) or project-local `.thor/grammars`?
2. **Hardlink fallback**: copy vs symlink when cross-filesystem?
3. **Nix integration**: Flake sets `grammar_dir`/`queries_dir` in derivation env, or user configures manually?
4. **Per-language override**: Should `thor.json` support per-language paths in addition to the directory? (e.g., `"grammars": {"odin": "/custom/path/odin.so"}`)

## Files changed

| File | Change |
|---|---|
| `treesitter/treesitter.odin` | Delete `GRAPHS_PATH`/`QUERIES_PATH` globals. Add `find_grammar(lang)` and `find_query(lang)` search procs. Update `ensure_parser` and `load_grammar` to use them. Add hardlink-to-configured-dir logic. |
| `site.odin` | `Config_File` and `Site` get `grammar_dir`/`queries_dir` fields. |
| `thor.json` | Optional `grammar_dir`/`queries_dir` fields. |
