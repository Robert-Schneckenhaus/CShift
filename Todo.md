# Todo

## 1. Build the CShift compiler in CShift itself (folder `selfhost/`)

Task: a new folder where the compiler is built with CShift. Add missing standard-library components (collections,
string operations, …) first. Structure the project sensibly (namespaces). If it turns out too difficult or important
language features are missing: say so, then decide together.

**Status:** see [selfhost/README.md](selfhost/README.md) (structure, design decisions, verification strategy).

Done:
- [x] Added to the stdlib/language what the compiler needs: `Main(string[] args)`, `string.FromCStr`, `Console.WriteError(Line)`,
      `Char.*`, `StringBuilder`, `HashSet<T>`, `Process.Run`; FFI: `ffiApi` (umbrella header), `char*` accepting a `const char*` parameter.
- [x] **Front end:** lexer, syntax tree (arenas) and parser in CShift (`selfhost/src/Syntax/`). Tokens and syntax tree are identical
      to the C++ compiler for all 110 `.csh` files of the repo (including the syntax-error tests and its own sources)
      (`selfhost/compare.sh`, part of `tests/run_tests.sh`).
- [x] **Back-end design:** `cshc` writes LLVM IR as **text** and calls clang (no LLVM inside the compiler; see selfhost/README.md and
      selfhost/DEPENDENCIES.md). The LLVM-C API via FFI would have worked too (a spike ran), but is heavier.
- [x] **Code generator:** `selfhost/src/Sema` (type table), `Emit` (IR writer), `CodeGen` (compiler state, type resolution, function
      instances, values and reference counting, expressions, calls/overloads, statements, structs, arrays, `Error<T>`/`Optional<T>`,
      `switch`, enums, generics and interfaces with constraints, `using`/`IDisposable`, pointers/`unsafe`, function pointers, the
      runtime as IR text) and `Main.csh` as the driver (`cshc [--stdlib dir] file.csh -o prog`). The standard library
      (`stdlib/*.csh`) is loaded as a prelude. **All 80 cases in `tests/cases` pass with `cshc`** (`--arc-stats` checks `live=0`),
      and so does `tests/test.csh` (output identical to `test.expected`). `selfhost/passing.txt` + `status.sh --check` guard
      against regressions.
- [x] **Bootstrap:** `cshc` compiles its own sources (`selfhost/bootstrap.sh`): stage 1 (built with the C++ compiler) and stage 2
      (built by `cshc`) produce **identical LLVM IR** for the sources of `cshc` (a fixed point), and stage 2 passes the same test
      cases. Part of `tests/run_tests.sh`.

Open (`bash selfhost/status.sh selfhost/bin/cshc -v` shows what's still missing; the message `cshc does not support …`
names the feature):
- [x] **Driver / projects** (done except for FFI): `cshc [options] files`, `cshc new|build|run` with `cshift.json`, `-c`, `--target`,
      `-l/-L/-I/-D`, libraries as inputs; added `Directory`, `Path`, `Process.RunCapture/GetEnv` to the stdlib; a JSON parser
      written in CShift; the stdlib is embedded in `cshc` (`selfhost/src/Driver/EmbeddedStdlib.csh` reads `stdlib/*.csh` at
      compile time with the new compiler functions `EmbedNames`/`EmbedTexts`, see below). `tests/projects` build with `cshc`
      (`selfhost/projects.sh`).
- [ ] Find clang the way `cshiftc` does: the bundled `toolchain/` next to `cshc` (this needs the path of its own executable, which
      is still missing; for now: `--cc`, `CSHIFT_CC`, PATH, MSYS2 folders).
- [x] **FFI (reading)**: `using X from "h.h"` and `from "x.ffi"` with `cshc`: loading `.ffi` files (`Driver/Ffi.csh`), C structs with
      explicit layout (`CodeGen/Layout.csh`), marshalling (`cstring`, `nullable`, `retCString`, `retOut`), ABI attributes for small
      integers, compiling and linking shims with clang. `tests/projects` (8 of 8) and `demo/` build with `cshc`.
- [ ] **FFI (generating)**: the `.ffi` file is currently generated from a header by the C++ compiler as a helper program
      (`cshiftc --ffi-prepare`, found via `--ffi-tool`, `CSHIFT_FFI_TOOL` or PATH). For a C++-free `cshc`, `FfiGenerator.cpp`
      (1600 lines, libclang) would have to be ported to CShift (calling libclang via FFI from CShift), or the `.ffi` files
      would have to be shipped along with the project.
- [ ] Once `cshc` can fully replace `cshiftc`: switch the release workflow and the docs over (C++ only as stage 0).

## 2. Test whether the new compiler can build everything

- [x] `tests/cases/` (80 of 80), `tests/test.csh` (identical output, no leaks) and the bootstrap run with `cshc`
      (`tests/run_tests.sh`, selfhost section; `selfhost/bootstrap.sh`: stage 1 = built with `cshiftc`, stage 2 = built by
      `cshc`, same IR for the sources of `cshc`).
- [x] `tests/projects/` (8 of 8, `selfhost/projects.sh`) and `demo/` build with `cshc` (header import goes through the C++
      helper program, see section 1).

## 3. Dependencies of the new compiler (analysis)

- [x] The analysis is in [selfhost/DEPENDENCIES.md](selfhost/DEPENDENCIES.md). In short: thanks to the IR-as-text approach, `cshc`
      itself no longer needs LLVM (only clang, to compile and link); C++/CMake are no longer needed to build it (a seed is
      needed for stage 0); clang as the linker driver can be replaced by lld on Windows; the C compiler for the FFI struct
      wrappers can be replaced by a hand-written ABI implementation; libclang stays optional (ship `.ffi` files instead); the
      C library stays.
- [ ] Implementation (only if wanted): lld instead of clang on Windows; a hand-written ABI implementation for structs passed
      *by value*, instead of the C wrappers.

## Other open items (from earlier sessions)

- [ ] The release workflow (`.github/workflows/release.yml`) has not fully run on Linux yet (Build and Tests passed, "Assemble"
      and "Test the assembled folder" were still open last time). The Linux job environment has `CSHIFT_SKIP_SELFHOST=1` set:
      remove it after the first fully green run, so the selfhost checks apply there too (they need `clang` in `PATH`).
- [ ] `demo/`: `libminifb.a` is not checked in (`demo/build-minifb.ps1` builds it); callbacks work, there are no lambdas yet.
- [ ] Language: lambdas/closures, interfaces as a value type, and a `List<T>` indexer are still open (see the README, "Known
      limitations").
