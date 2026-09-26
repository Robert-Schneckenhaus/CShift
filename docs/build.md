# Projects and the build

The language design document (§34) defines *what* the build does (compiling, monomorphization, optimizing, linking,
FFI, libraries), but not *how* a project is described. This document fills that gap.

## Basic model

* A program consists of **all** `.csh` files passed to it; there are no headers and no translation units in the C
  sense. The compiler analyzes the whole program at once (symbols are resolved globally, generics are instantiated
  per type combination) and writes **one** object file, which it then links.
* Because of that, a project only needs, at its core: a name, the source files, the target (a program or an object
  file), the optimization level, and any extra libraries.
* There is no incremental build or inter-project dependencies (yet). At the program's current size, a full rebuild
  is fast (on the order of 0.2 s).

## Stage 1 (implemented): the declarative project file `cshift.json`

```json
{
	"name": "demo",
	"version": "0.1.0",
	"type": "executable",
	"sources": ["src"],
	"output": "bin/demo",
	"optimize": 2,
	"links": ["sqlite3"],
	"target": "x86_64-w64-windows-gnu"
}
```

| Key | Meaning | Default |
|---|---|---|
| `name` | the project name (letters, digits, `_ - .`); required | – |
| `version` | version (informational only) | – |
| `type` | `"executable"` (link a program) or `"object"` (object file only) | `"executable"` |
| `sources` | a list of files and folders; folders are searched recursively for `*.csh`, paths are relative to `cshift.json` | `["src"]` |
| `output` | the output path without an extension (`.exe`/`.obj`/`.o` is added depending on the platform) | `"bin/<name>"` |
| `optimize` | 0–3 (like `-O0` … `-O3`) | `2` |
| `links` | libraries for the linker: a name (`-l<name>`) or a file (`libs/libminifb.a`, `x.o`, `x.lib`; has a path or extension); in addition to `link "name"` in source code | `[]` |
| `includePaths` | search paths for C headers (`using X from "h.h"`), relative to `cshift.json` | `[]` |
| `defines` | macros used when parsing C headers (`NAME`, `NAME=value`) | `[]` |
| `libraryPaths` | linker search paths (`-L`) | `[]` |
| `ffiApi` | path fragments of C headers that belong to the imported API even when they live in system paths (`--ffi-api=`, see [ffi.md](ffi.md)) | `[]` |
| `target` | the target triple | host |

Unknown keys produce a warning, invalid values an error naming the file. `$schema` is allowed; the VS Code extension
ships a schema that validates and auto-completes `cshift.json`.

### Commands

```
cshiftc new <folder>           a new project (cshift.json, src/main.csh, .gitignore)
cshiftc build [project]        build it
cshiftc run   [project]        build and run it
cshiftc [options] a.csh b.csh  single files without a project (as before)
```

`project` is a folder containing `cshift.json`, or the path to the file. Without it, `cshift.json` is looked up in
the current folder and its parent folders. Command-line options (`-O2`, `--target`, `-o`, `--cc`, `-l…`, `-v`)
override the file.

### Why JSON?

* **No code needed** to read the project: the compiler understands it directly (LLVM already brings a JSON parser
  along, so this adds no new dependency). YAML would need to bring its own parser; Makefiles are platform-dependent
  and too powerful for a single-program model.
* **Editor support** via a JSON schema (completion, errors while typing).
* As a plain data model, it also becomes the intermediate format for stage 2 later.

## Stage 2 (idea): a build written in the language itself, like Zig

For cases a single file can't express (sources conditional on the platform, code generation before the build,
multiple targets, dependencies, tests), a `build.csh` sits next to, or instead of, `cshift.json`:

```csharp
using System.Build;

Error<void> Build(ref Builder b)
{
    var exe = b.AddExecutable("demo");
    exe.AddSources("src");
    exe.Link("sqlite3");
    exe.SetOptimize(2);

    if (b.Target().IsWindows())
        exe.AddSources("platform/windows");

    var tests = b.AddExecutable("demo-tests");
    tests.AddSources("src", "tests");
    b.AddRunStep("test", tests);
    return;
}
```

This is how it would work:

1. `cshiftc build` finds a `build.csh` and compiles it **together with the standard library and a small
   `System.Build` module** into a temporary program.
2. That program is run; `Build(...)` describes the targets. The result is exactly the data model from stage 1 (one
   or more project descriptions with the same fields), which the compiler then builds.
3. The language itself is the scripting language; there's no second format to learn.

The standard library already has what this needs at the language level — `Process.Run`/`RunCapture`/`GetEnv`/`IsWindows`,
`Directory`/`Path`, and `Main(string[] args)` for command-line arguments — plus a JSON parser (used to read
`cshift.json` itself). What's still missing is the `System.Build` module described above (a thin, typed layer over
that data model) and named steps (`cshiftc build test`). Until then, `cshift.json` stays the standard way; stage 2
doesn't replace it, it complements it for special cases.

## Open items

* Multiple targets in one `cshift.json` (e.g. a program plus tests), `cshiftc test`.
* Dependencies between projects and packages (pulling in the source folder of another project).
* An intermediate `obj/` directory, incremental builds (only useful once translation units are separated).
* Variables/conditions in the project file (`"sources"` per platform) — or handle that directly via `build.csh`.
