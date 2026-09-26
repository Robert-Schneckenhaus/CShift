# The compiler

← [Documentation](README.md)

`cshiftc` is written in CShift ([selfhost/](../selfhost/README.md)). It parses and checks the program, writes
**LLVM IR as text** and calls **clang**, which optimizes it, generates machine code and links. The compiler itself
therefore contains no LLVM (a few MB instead of the 120 MB of the first compiler); LLVM only lives in the bundled
clang.

```
source (.csh) ─▶ lexer ─▶ parser ─▶ syntax tree ─▶ type checking + code generation ─▶ LLVM IR (text) ─▶ clang ─▶ program
```

## Stages and the frozen C++ compiler

The first compiler was written in C++17 against the LLVM API ([compiler/](../compiler/README.md)). It is **frozen**:
its only job is to be stage 0 of the bootstrap when no `cshiftc` release is at hand.

| Stage | What | Built by |
|---|---|---|
| 0 | the C++ compiler (`build/cshiftc`) | CMake, a C++17 compiler, the LLVM development packages |
| 1 | the self-hosted compiler (`cshc`) | stage 0 |
| 2 | the self-hosted compiler again: **the released `cshiftc`** | stage 1 |

`selfhost/build-release.sh <stage0> <version> <out>` runs stages 1 and 2 and the bootstrap check: stage 1 and stage 2
must generate identical IR for the compiler's own sources. The release workflow
([.github/workflows/release.yml](../.github/workflows/release.yml)) does exactly this and ships stage 2.

Two rules follow from the freeze:

* New language features exist only in the self-hosted compiler. `selfhost/` and `stdlib/` must stay within the
  language of the C++ compiler, because stage 0 compiles both (the standard library is the prelude of every program,
  including `cshc` itself). Generic bodies are only compiled when they are used, so stdlib generics may use newer
  features as long as `cshc` does not instantiate them (`Mutex<T>` does this).
* Once a self-hosted release exists, it can replace stage 0 (`cshiftc build selfhost`), and `selfhost/` may use every
  feature that release knows. Then `compiler/` can be retired.

## Structure

The file-by-file tour is in [selfhost/README.md](../selfhost/README.md). In short:

| Folder | Contents |
|---|---|
| `selfhost/src/Syntax` | lexer, syntax tree (arenas of nodes, handles), parser, token/tree dumps |
| `selfhost/src/Sema` | the type table: types are interned integers |
| `selfhost/src/Emit` | the IR writer (text) |
| `selfhost/src/CodeGen` | declarations, type resolution, generics (monomorphization), expressions, calls, statements, ARC, `Error<T>`/`Optional<T>`, threads, lambdas, interface values, the constant evaluator, the runtime as IR |
| `selfhost/src/Driver` | command line, `cshift.json`, finding clang and the bundled toolchain, `.ffi` files and the header import |
| `selfhost/native` | `host.c`: libclang (loaded at run time), the path of the executable, reading the embedded toolchain |
| `stdlib/` | the standard library, in CShift, embedded into the compiler |

There is no separate type-checking pass: checking and code generation happen in one walk over the syntax tree
(generic bodies are walked again for every instantiation, like C++ templates). A separate semantic pass is on the
[to-do list](../Todo.md). The compiler stops at the first error.

**Reference counting:** variables, fields and array elements own a reference; intermediate results carry a "+1" that
is taken over when stored or released at the end of the statement. Arguments are passed borrowed; the called function
retains its own parameters. Heap blocks (strings, arrays, closure environments, interface boxes) start with
`{int64 count, int64 length}`. `--arc-stats` prints the balance of allocations and frees at the end of the program.
Only `SharedPtr<T>` counts atomically.

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
  IR (`selfhost/bootstrap.sh`), and - if the C++ stage 0 is present - its front end still agrees with the C++ one on
  every file (`selfhost/compare.sh`; files with newer syntax are listed in `selfhost/frontend-skip.txt`).

## What the compiler needs

| Dependency | What for | Status |
|---|---|---|
| clang (+ libLLVM) | optimizing the IR, machine code, linking; compiling the C wrappers of the header import | bundled in the releases (`toolchain/`) |
| lld | linking | bundled (Windows); Linux uses the system linker (`build-essential`) |
| libclang | `using X from "header.h"` (loaded at run time, only when a header is imported) | bundled; `.ffi` files can be shipped instead |
| C library and headers | the runtime of the programs (`malloc`, `printf`, `fopen`, pthreads) | Windows: MinGW-w64 in the release; Linux: the system |
| C++, CMake, LLVM development packages | only stage 0 | not needed once a self-hosted release is the seed |

Possible reductions, none of them needed so far: calling lld directly instead of the clang driver (easy on Windows,
distribution-dependent on Linux); implementing the C calling conventions for structs passed by value in the compiler
(SysV and Win64, a few hundred lines each) instead of generating C wrappers. Replacing LLVM, libclang or the C library
is not worth it.
