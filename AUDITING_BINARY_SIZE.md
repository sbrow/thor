# Visualizing & Managing `thor` Binary Size

How to inspect what makes up the compiled `thor` binary, and how to keep that
inspection useful once we bundle layout/asset files into the binary.

## Quick inspection (tools already available)

The binary is a not-stripped ELF, so it ships symbols we can break down.

```bash
# Section totals (text / data / bss)
size ./thor

# Top symbols by size
nm --print-size --size-sort --radix=d ./thor \
  | awk '{sz=$2+0; sub(/^[0-9a-fA-F]+ +[0-9]+ +[A-Za-z] +/,""); printf "%8d  %s\n", sz, $0}' \
  | sort -rn | head -25

# Aggregate symbol sizes by Odin module namespace (foo::bar -> "foo")
nm --print-size --size-sort --radix=d ./thor \
  | awk '{sz=$2+0; rest=$0; sub(/^[0-9a-fA-F]+ +[0-9]+ +[A-Za-z] +/,"",rest);
          ns=rest; if (rest ~ /::/){sub(/::.*/,"",ns)}
          else if (rest ~ /^ts_/){ns="treesitter (ts_*)"} else {ns="<other/runtime>"};
          s[ns]+=sz} END{for (k in s) printf "%9d  %s\n", s[k], k}' \
  | sort -rn | head -25
```

As of this writing the top contributors were: tree-sitter tables (~118 KB),
`main` (~96 KB), runtime/other (~93 KB), `mustache` (~67 KB), then `fmt` /
`encoding_json` from the stdlib.

## Better visualization: `bloaty`

`bloaty` (Google's binary-size profiler) is the right tool. Not installed, but
runnable via Nix:

```bash
bloaty ./thor                      # by section
bloaty ./thor -d symbols -n 30     # by symbol, hierarchical
bloaty ./thor -d sections,symbols  # section then symbols within each
# via nix (no install):
nix run nixpkgs#bloaty -- ./thor -d symbols -n 30
```

For a stripped-size estimate:

```bash
readelf -S ./thor | grep -E 'debug|symtab|strtab'   # strippable overhead
strip -s ./thor -o thor.stripped && size thor.stripped
```

Odin also supports smaller builds: `odin build . -o:size -no-bounds-check`.

## IMPORTANT: keeping bloaty useful once we bundle layouts into the binary

Today the VFS (`vfs.odin`) reads layout/asset files lazily from disk at runtime
(`VFS_Entry.fs_path` + `os.read_entire_file_from_path`); `VFS_Entry.data` is
never populated at build time. So embedded content is **not** in `./thor` yet.

When we switch to embedding via Odin `#load(...)`, the file bytes land in the
binary's `.rodata` section. Whether bloaty can show *per-file* sizes depends on
how we emit the embed:

- **Section total — always visible.** `.rodata` grows by ~the total bundled
  size. `bloaty ./thor -d sections` (or `size`) shows the aggregate, and we can
  diff before/after. This always works.

- **Per-file breakdown — only if each file is a NAMED symbol.**
  - A generated `map[string]VFS_Entry` literal full of inline `#load(...)`
    expressions makes each blob an **anonymous** `.rodata` constant. Bloaty
    lumps them together — no per-file breakdown.
  - Assigning each file to its own **package-level variable** makes each a named
    global symbol, so `bloaty ./thor -d symbols` (and the `nm` recipe above)
    show each file individually:

    ```odin
    layout_base_html   := #load("defaults/layouts/base.html")
    layout_single_html := #load("defaults/layouts/single.html")
    // ...then reference these in the VFS map instead of inlining #load.
    ```

### Decision to bake into the bundling codegen

When we build the codegen that replaces the runtime `mount_dir` disk walk, have
it emit **one named package-level variable per embedded file** (not an anonymous
map literal). That single choice is what makes bloaty / `nm` per-file analysis
possible — cheap to do up front, painful to retrofit.

Additional options that help regardless of symbolization:

1. Build with Odin `-debug` (DWARF) and use `bloaty ./thor -d compileunits` to
   attribute embedded bytes to the generated source file.
2. Since the generator already knows every file and its size, emit a size
   manifest at bundle time (`path -> bytes`, sorted / treemap). This is the most
   reliable per-file view and can't drift from reality; bloaty then just
   confirms the `.rodata` total matches.
