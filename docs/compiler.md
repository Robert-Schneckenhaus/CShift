# The compiler

← [Documentation](README.md)

`cshiftc` is written in CShift ([selfhost/](../selfhost/README.md)). It parses and checks the program, writes
**LLVM IR as text** and calls **clang**, which optimizes it, generates machine code and links. The compiler itself
therefore contains no LLVM (a few MB instead of the 120 MB of the first compiler); LLVM only lives in the bundled
clang.

```
source (.csh) ─▶ lexer ─▶ parser ─▶ syntax tree ─▶ type checking + code generation ─▶ LLVM IR (text) ─▶ clang ─▶ program
```

## Stages

The compiler builds itself. Stage 0 is an earlier release: the version in
[selfhost/stage0.txt](../selfhost/stage0.txt), downloaded by
[selfhost/fetch-stage0.sh](../selfhost/fetch-stage0.sh) (or any `cshiftc` named by `CSHIFT_STAGE0`).

| Stage | What | Built by |
|---|---|---|
| 0 | a released `cshiftc` (version in `selfhost/stage0.txt`) | downloaded |
| 1 | the self-hosted compiler (`cshc`) | stage 0 |
| 2 | the self-hosted compiler again: **the released `cshiftc`** | stage 1 |

`selfhost/build-release.sh <stage0> <version> <out>` runs stages 1 and 2 and the bootstrap check: stage 1 and stage 2
must generate identical IR for the compiler's own sources. The CI workflow
([.github/workflows/ci.yml](../.github/workflows/ci.yml)) does this for every pull request, the release workflow
([.github/workflows/release.yml](../.github/workflows/release.yml)) also packages and ships stage 2.

Two rules follow:

* `selfhost/` may use the language of the stage 0 version and no newer feature: stage 0 compiles it (stage 1). To
  use a new feature in the compiler, release it first, then raise `selfhost/stage0.txt`.
* Stage 0 builds stage 1 against **its own** (embedded) standard library, stage 1 builds stage 2 against the one in
  `stdlib/`. So `stdlib/` may use everything the current compiler knows, and the compiler's sources must work with
  both libraries: when a library function changes its result (e.g. `Trim()` returning a `StringSlice` instead of a
  `string`), they use a form that fits both (`s.Trim().ToString()`).

The first compiler, written in C++17 against the LLVM API, bootstrapped the self-hosted one and was retired after
version 0.04 (it is in the git history).

## Structure

The file-by-file tour is in [selfhost/README.md](../selfhost/README.md). In short:

| Folder | Contents |
|---|---|
| `selfhost/src/Syntax` | lexer, syntax tree (arenas of nodes, handles), parser, token/tree dumps |
| `selfhost/src/Sema` | the type table: types are interned integers |
| `selfhost/src/Emit` | the IR writer (text) |
| `selfhost/src/Check` | the checker: names and types of every function body before code generation, so that one run reports all errors ([semantic pass](semantic-pass.md)) |
| `selfhost/src/CodeGen` | declarations, type resolution, generics (monomorphization), expressions, calls, statements, ARC, `Error<T>`/`Optional<T>`, threads, lambdas, interface parameters, sum types, the constant evaluator, the runtime as IR |
| `selfhost/src/Driver` | command line, `cshift.json`, finding clang and the bundled toolchain, `.ffi` files and the header import |
| `selfhost/native` | `host.c`: libclang (loaded at run time), the path of the executable, reading the embedded toolchain |
| `stdlib/` | the standard library, in CShift, embedded into the compiler |

Before code generation, the checker (`selfhost/src/Check`) walks every function body of the program and reports all
the errors it finds, continuing after each one; the decisions (result types, conversions, overloads) are functions
that it shares with code generation (`CodeGen/Rules.csh`). It is being built step by step into a full semantic pass,
see [semantic-pass.md](semantic-pass.md): what it does not check yet is still checked by code generation, which stops
at its first error. Generic bodies are walked again for every instantiation, like C++ templates.

**Reference counting:** variables, fields and array elements own a reference; intermediate results carry a "+1" that
is taken over when stored or released at the end of the statement. Arguments are passed borrowed; the called function
retains its own parameters. Heap blocks (strings, arrays, closure environments) start with
`{size count, size length}`. `--arc-stats` prints the balance of allocations and frees at the end of the program.
Only `SharedPtr<T>` counts atomically.

**Targets:** `size` is the pointer-sized integer of the target (`selfhost/src/Emit/Target.csh`): `i64` on 64-bit targets
(the default, the host), `i32` for a `--target` triple with 32-bit pointers (`i686-linux-gnu`, `m68k-…`, `arm…`). It
is the type of lengths, indexes and sizes in the generated code, of `nint`/`nuint` and of the length in a slice; the
sizes and alignments of types follow the target's data layout. The language does not change: `Length` is `int32`,
`int64` exists on every target (a 64-bit index on a 32-bit target that does not fit fails the bounds check).
Tested: i686 Linux (the whole test suite, a 32-bit cshc rebuilds itself) and 32-bit big-endian PowerPC under qemu.
m68k works for small programs; LLVM's m68k backend is still experimental (only the small code model: data more than
32 KB away does not link; some larger programs are miscompiled, also by the bundled clang 22).

## Tests

```
tests/run_tests.sh [path/to/cshiftc] [-O0..-O3]     # default: build/stage2/cshiftc, then selfhost/bin/cshc
```

* `tests/test.csh` (+ `tests/mathlib.csh`): a large program with ~165 checks; output and ARC balance are compared.
* `tests/cases/*.csh`: small programs with their expectations in comments (`// expect-error:`, `// expect-exit:`,
  `// expect-stdout:`, `// expect-stderr:`): compiler errors (`err_*`), panics (`panic_*`), features and the standard
  library.
* `tests/projects/*`: projects built with `cshiftc build|run`, some with C code (`native/*.c`) for the header import.
* The selfhost section builds the compiler with the compiler under test and checks: all cases pass with it
  (`selfhost/status.sh`, `passing.txt`), the projects build (`selfhost/projects.sh`), it rebuilds itself to the same
  IR (`selfhost/bootstrap.sh`).
* `CSHIFT_TARGET=i686-linux-gnu tests/run_tests.sh` runs everything as 32-bit code (needs the 32-bit C library, e.g.
  `gcc-multilib`); the selfhost section then also builds a 32-bit compiler. Output that depends on the size of pointers
  (`sizeof`) is checked with `// expect-stdout-64:` / `// expect-stdout-32:`.

## What the compiler needs

| Dependency | What for | Status |
|---|---|---|
| clang (+ libLLVM) | optimizing the IR, machine code, linking; compiling the C wrappers of the header import | bundled in the releases (`toolchain/`) |
| lld | linking | bundled (Windows); Linux uses the system linker (`build-essential`) |
| libclang | `using X from "header.h"` (loaded at run time, only when a header is imported) | bundled; `.ffi` files can be shipped instead |
| C library and headers | the runtime of the programs (`malloc`, `printf`, `fopen`, pthreads) | Windows: MinGW-w64 in the release; Linux: the system |
| an earlier `cshiftc` release | stage 0, only to build the compiler from source | downloaded (`selfhost/fetch-stage0.sh`) |

Possible reductions, none of them needed so far: calling lld directly instead of the clang driver (easy on Windows,
distribution-dependent on Linux); implementing the C calling conventions for structs passed by value in the compiler
(SysV and Win64, a few hundred lines each) instead of generating C wrappers. Replacing LLVM, libclang or the C library
is not worth it.
