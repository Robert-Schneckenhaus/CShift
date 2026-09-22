# Dependencies of a self-hosted compiler (analysis)

Question from the todo list: what does the new compiler need once it's shipped? Can that be reduced, or can the
dependencies themselves be written in CShift? This is an assessment, not yet an implementation.

## What the current compiler needs

| Level | What for | Size (Windows) |
|---|---|---|
| **LLVM** (statically linked into `cshiftc`) | build IR, optimize, generate object files | ~120 MB in the program |
| **clang** | linker driver (finds startup files, calls lld), C compiler for the FFI struct wrappers | `clang.exe` is small, but `libLLVM` (150 MB) + `libclang-cpp` (60 MB) |
| **lld** | actual linking | 6 MB |
| **libclang** | reading C headers (`using X from "h.h"`) | 35 MB (+ the two LLVM DLLs) |
| **C library and headers** | runtime of the generated programs (`malloc`, `printf`, `fopen`, …) and headers for FFI | Windows: MinGW-w64 (~70 MB, included in the release); Linux: the system's `libc6-dev` |
| **C++ compiler, CMake** | only to *build* `cshiftc` | not needed at runtime |

## The compiler in CShift: what changes

1. **C++ and CMake are no longer needed to build it.** `cshc` builds itself with `cshiftc build selfhost` (later with
   itself). What's left is the chicken-and-egg problem: the first stage ("stage 0") needs an already-existing compiler.
   Solutions: ship a ready-built `cshc` (a release) as the seed, or keep the seed as LLVM IR/an object file in the
   repository. After that, C++ is no longer needed.
2. **LLVM only lives inside clang.** The back-end part (code generation for x86-64/ARM, the optimizer, object formats)
   is not something to rewrite in CShift — that would be years of work. But `cshc` doesn't need to embed LLVM at all:
   it writes the IR as **text** (`.ll`) and hands it to `clang`, which optimizes it, generates the object code and
   links it (this is already how `selfhost/` works). That removes the static LLVM link inside the compiler
   (`cshiftc` is currently ~120 MB, `cshc` a few MB); LLVM only remains as part of the bundled toolchain
   (`clang` + `libLLVM`). The alternative — calling the LLVM-C API directly from CShift (this works via FFI: a
   CShift program built that way produced a working program) — would bring a 100 MB link and an `unsafe` wrapper
   around every call, and was rejected for that reason. Downside of the text route: clang has to be present when
   compiling every program (it already is, for linking), and writing and parsing IR text is somewhat slower than
   the API.
3. **clang as the linker driver can be replaced by lld.** `cshc` would call `ld.lld` (or `lld-link`) itself with the
   right startup files and libraries. Windows/MinGW is manageable (`crt2.o`, `libmingw32`, `libmoldname`,
   `libmingwex`, `libmsvcrt`/`libucrt`, `libkernel32`, … plus `libclang_rt.builtins`); on Linux it depends on the
   distribution (multiarch paths, gcc startup files `crtbegin.o`, the dynamic loader) — there, the clang driver is
   the pragmatic solution. Assessment: yes for Windows (small effort), Linux later or not at all.
4. **The C compiler for the struct wrappers is replaceable.** They exist only because calling C functions with
   structs passed *by value* is platform-dependent. `cshc` could generate these calls directly as IR if it
   implemented the calling convention itself (SysV x86-64: classifying arguments as INTEGER/SSE/MEMORY; Win64: 1/2/4/8
   bytes in registers, otherwise by pointer). That's manageable (a few hundred lines per convention) and removes the
   dependency on `clang` for FFI. Medium effort, benefit: no C compiler needed at runtime any more.
5. **libclang is optional and should stay that way.** It's only needed for `using X from "header.h"` and is loaded at
   runtime. Writing a C preprocessor and C parser in CShift that understands real headers (`windows.h`, glibc, SDL,
   …) would be very large and never complete (macros, attributes, `__declspec`, bit fields, platform-dependent
   layout). Recommendation: keep libclang; anyone who doesn't want to import a header doesn't need it, and the
   generated `.ffi` files can be shipped with the project (the compiler reads them without libclang). A `.ffi` file
   is plain JSON: reading it just needs a JSON parser (small, writable in CShift). **Status:** `cshc` reads `.ffi`
   files itself (`selfhost/src/Driver/Ffi.csh`); only *generating* one from a header still goes through the C++
   compiler as a helper program (`cshiftc --ffi-prepare`). Without it, a project needs its `.ffi` files shipped
   along.
6. **The C library of the generated programs stays.** On Linux it's the ABI to the system, and on Windows (ucrt) it's
   part of the operating system. Replacing it would mean writing number formatting (`double` → text needs an
   algorithm like Ryu), `strtod`, the math functions, and a custom memory allocator on top of `HeapAlloc`/`mmap` —
   feasible, but its own sub-project with hardly any payoff.
7. **What's already CShift/IR anyway:** the standard library (List, Dictionary, File, String, …) is CShift code; ARC,
   strings and panics are generated as IR — there is no bundled runtime library.

## Assessment

| Dependency | replaceable? | effort | recommendation |
|---|---|---|---|
| C++ compiler, CMake (to build it) | yes, by the compiler itself | small, once code generation is in place (needs a seed) | yes |
| LLVM (optimizer, code generation) | no, but only lives inside clang now: `cshc` writes IR text | – | keep clang; `cshc` no longer needs LLVM |
| clang as the linker driver | Windows yes (lld directly), Linux hard | small to medium | switch Windows over later |
| clang as the C compiler for FFI wrappers | yes (a hand-written ABI implementation) | medium | worth it if clang should go away otherwise |
| libclang (reading headers) | technically yes, practically no | very large | leave it optional; ship `.ffi` files |
| C library | yes, but pointless | large | keep it |

What would ship, then: **`cshc` (small, without LLVM) + the toolchain made of `clang` and `libLLVM`** (Windows
additionally needs the MinGW headers/libraries; Linux needs `build-essential`), with `libclang` optional. If clang as
the linker driver (point 3) and as the C compiler for the FFI wrappers (point 4) go away, all that's left for
compiling is `clang` itself (optimization and object code from the IR) plus lld; writing a replacement for LLVM
itself is not worth it.
