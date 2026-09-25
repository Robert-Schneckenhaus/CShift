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

## 4. Threads (`thread`, `Thread`/`Thread<T>`, `SharedPtr<T>`)

Task: real OS threads. A `thread`-marked function can only be called through `start` (`start Foo(args)`); a plain
call is a compile-time error. `start` spawns it on its own OS thread and returns a handle (`Thread` for `void`,
`Thread<T>` otherwise) instead of running it directly; see
[docs/language/threading.md](docs/language/threading.md) for the full language-level description.

**Status:** done in `cshiftc` (the C++ compiler) only, by deliberate choice — this is by far the largest feature
added in one pass this session (a new keyword, a new ARC-participating type, a compile-time purity/call-graph
checker, a per-function compiler-generated trampoline, and real pthread-based synchronization), and porting it to
the self-hosted `cshc` as well in the same pass risked a rushed, under-tested port that could break `cshc`'s
hard-won self-compiling fixed point (`selfhost/bootstrap.sh`). `cshc`/`selfhost/` are **unaffected**: they still
build and bootstrap exactly as before.

Done (`cshiftc`):
- [x] `thread` keyword: a modifier on a free function or a `static` struct method (not an instance method, not
      generic, not variadic, not `extern`). Lexer/AST/Parser/`DumpAst`.
- [x] `start f(args)`: the only way to call a `thread` function — a plain call is a compile-time error
      (`CodeGen::emitCall`'s `viaStart` parameter). `start` is a *contextual* keyword (recognized only directly in
      front of a call, i.e. an identifier spelled `start` immediately followed by another identifier —
      `Parser::parseUnary`), not a reserved word, since `start` is already a common parameter/variable name in the
      existing stdlib (`Substring(int start, ...)` and similar).
- [x] `SharedPtr<T>`: a new built-in generic type (like `Error<T>`/`Optional<T>`), a heap block
      `{atomic i64 refcount, T value}`, atomic retain/release (`CodeGenRuntime.cpp`: `retainSharedFn`, the
      `isSharedPtr()` branch of `releaseFor`). `SharedPtr<T>.Create(value)`, `.Get()`, `.Ptr()` (`unsafe`),
      `.IsNull()` (`CodeGenCall.cpp`).
- [x] Signature checks (`CodeGenThread.cpp`: `checkThreadSignature`, called from `ensureSignature`):
      `ref`/`const ref` parameters rejected; parameters restricted to plain value types or `SharedPtr<T>`
      (`isThreadSafeType`, recursive through structs/`Optional<T>`) — this is what rules out raw pointers,
      `Action`/`Func`, strings, arrays and the built-in containers (their reference counts are not atomic) as
      thread parameters, while still allowing a mixed struct of value fields and `SharedPtr<T>` fields.
- [x] Purity check (`checkThreadPurity`): a `thread` function (and everything it calls, directly or not) may
      never read or write a global variable. Reuses the call-graph data (`codeUses`) that
      `checkGlobalInitOrder()` already collects — the same "does this reach a global" BFS, started from a
      different place and reporting a different problem, rather than a second, separate analysis.
- [x] Spawning (`emitThreadSpawn`, `threadTrampolineFor`): allocates the control block shared with the worker
      thread (in the exact layout `SharedPtr<T>` uses, so it is released through the normal `SharedPtr<T>`
      machinery), packs the arguments, and calls `pthread_create` with a small per-function trampoline
      (`__cs_thread_start.<name>`) that detaches itself, unpacks the arguments, calls the real function, stores
      the result and marks completion. `-lpthread` is now linked unconditionally (`main.cpp`), the same library
      name works on both Linux and the MSYS2 CLANG64/MinGW toolchain (both ship `libpthread`).
- [x] `Thread.Cancelled`, usable only directly inside a `thread` function's own body (`emitThreadCancelled`):
      reads a thread-local variable (`__cs_thread_current_core`) the trampoline sets before calling the function.
- [x] `Thread`/`Thread<T>` themselves are almost entirely ordinary CShift code (`stdlib/thread.csh`): the
      mutex/condition-variable protocol (`_ThreadCore`/`_ThreadControl<T>`, using `pthread_mutex/cond_*` added to
      `native.csh`), `Join`/`Cancel`/`CancelAndWait`/`IsCompleted`/`IsCancelled`. Bare `Thread` (the `void` case)
      is internally a separate struct, `_ThreadVoid` — this codebase's structs cannot be overloaded by
      type-argument count, so the compiler maps the spelling `Thread` (no type argument) to it
      (`CodeGen::resolveType`/`resolveStaticTarget`).
- [x] `is` pattern on `Thread<T>` (`CodeGen::emitIs`): non-blocking, `false` while running and `false` once
      cancelled (even if the function still returned a value) — implemented by calling `Thread<T>`'s private
      `_TryGetResult()` (returns `Optional<T>`) and reusing the existing `Optional<T>` pattern-match code path.
      No `if (thread)`/`if (!thread)` conversion (simply not implemented, as requested).
- [x] Tests: `tests/cases/thread_basic.csh`, `thread_cancel.csh` (`Cancel`/`CancelAndWait`/`Thread.Cancelled`/
      `SharedPtr<T>` parameter), `thread_static_method.csh`, `thread_start_contextual.csh` (`start` still works as
      an ordinary identifier), `shared_ptr.csh`, and the rejections (`err_thread_global.csh`,
      `err_thread_ref_param.csh`, `err_thread_unsafe_param.csh`, `err_thread_instance_method.csh`,
      `err_thread_function_pointer.csh`, `err_thread_bare_call.csh`, `err_start_non_thread.csh`).

Open:
- [ ] Port to `cshc`/`selfhost/` (a separate follow-up; the user chose `cshiftc`-only for this pass — see above).
- [ ] The `pthread_mutex_t`/`pthread_cond_t` storage inside `_ThreadCore` is a generous fixed-size blob (8×`int64`
      each, 64 bytes) sized for glibc's actual layout, not the (much smaller) footprint MinGW's winpthreads
      needs; correct on every platform tested, just not tight.
- [ ] No general-purpose synchronization primitives (a standalone `Mutex`/condition variable, channels) — only
      what `Thread`/`Thread<T>` need internally exists so far.

## 5. Distribution: a standalone single-file executable, and (documented only) a lighter libclang-free variant

Prompted by: "clang is big" for something that is only used to extract FFI declarations from C headers - see
whether libclang is worth it, and whether a single, self-contained executable is possible.

**libclang alternatives (Tree-sitter's C grammar, "CppParser"-style heuristic parsers): investigated, not enough.**
`FfiGenerator.cpp` needs real preprocessing (macros, `#include`, `-D`), constant-expression evaluation (enum
values), and ABI-aware struct layout (`sizeof`/`alignof`/`offsetof`, bitfields, `#pragma pack`) - genuine semantic
analysis, not parsing. Tree-sitter's C grammar is syntax-only and explicitly does not expand macros in general
([tree-sitter/tree-sitter-c#7](https://github.com/tree-sitter/tree-sitter-c/issues/7),
[#108](https://github.com/tree-sitter/tree-sitter-c/issues/108)); "CppParser" turned out to be an ambiguous name
for several unrelated, syntax-only C/C++ header parsers, same gap. Real precedent for what a from-scratch
alternative actually costs: Zig wrote **Aro**, a genuine C compiler frontend (own preprocessor, own Sema, C23),
specifically to move `translate-c` off Clang - a years-long, dedicated project
([ziglang/zig#16268](https://github.com/ziglang/zig/issues/16268)), not a lightweight parser swap.

**Standalone single-file executable: done**, as a release artifact *alongside* the existing
`toolchain/`-folder archives (kept as they are).
- [x] `packaging/make-standalone.sh`: appends the same `toolchain/` folder `package-windows.sh`/`package-linux.sh`
      already produce, gzip-compressed, after the compiler's own executable image, with a 16-byte footer
      (magic `CSFTTC01` + little-endian archive size). Both the PE and the ELF loader only read what their own
      headers declare, so trailing bytes are simply ignored - the same trick self-extracting installers (NSIS,
      7z SFX, makeself) and AppImage use.
- [x] `compiler/src/main.cpp` (`findEmbeddedToolchain`, `extractEmbeddedToolchain`, `toolchainCacheDir`,
      `bundledClang`): on first use that actually needs the toolchain (linking, or `using X from "header.h";`),
      reads its own footer, extracts the embedded archive with the system `tar` (present on Windows since 10
      1803, and on every Linux/macOS install - far simpler and more robust than hand-rolling a gzip/tar reader
      for a one-time, best-effort setup step) into a per-user, per-version cache directory
      (`%LOCALAPPDATA%\cshift\toolchain-<version>` / `$XDG_CACHE_HOME/cshift/toolchain-<version>` or
      `~/.cache/...`), then uses it exactly like the regular `toolchain/`-next-to-the-exe folder. Every run after
      the first just finds it already there.
- [x] Verified end to end on Windows (real clang/lld/DLLs, `clang.exe`/`ld.lld.exe` hidden from `PATH`): the
      self-extracted toolchain is genuinely found and invoked, not silently falling back to something else.
      (linking itself failed in that specific manual test only because of an incomplete hand-copied toolchain
      subset for the test, not the extraction mechanism - the exact same failure was reproduced through the
      existing, unmodified `toolchain/`-next-to-exe path with the same incomplete files, confirming the new code
      is not the cause; `make-standalone.sh` itself packages the *real*, already-correct `package-windows.sh`
      output, so a real release build is unaffected.)
- [x] Wired into `.github/workflows/release.yml`: both the `windows` and `linux` jobs now also build the
      standalone executable and test it in a clean environment (no PATH toolchain, no pre-existing cache - it has
      to self-extract), uploaded as `windows-x64-standalone`/`linux-x64-standalone`; `publish` lists them
      alongside the regular archives. **Not yet validated by an actual CI run** (this workflow already has a
      standing item below about Linux not having fully run yet).
- [ ] Linux is "standalone" in the same sense as its regular archive already is, not more: `package-linux.sh`'s
      toolchain relies on the host's glibc and binutils (`build-essential`), so the single file still is not
      fully hermetic there. Only Windows becomes genuinely zero-dependency.
- [ ] The cache directory is never cleaned up automatically (each version gets its own, so upgrades do not reuse
      a stale one, but old versions' extracted copies just accumulate). Fine for now; a `cshiftc --clear-cache` or
      similar could be added later if it becomes a real nuisance.

**Lighter, libclang-free `cshiftc` variant + a downloadable `.ffi` file repository: documented here, not started
(as requested).** The idea: a build of `cshiftc` without libclang support at all (smaller download, no clang
dependency for anything other than linking), which for `using Name from "header.h";` would fetch a pre-generated
`.ffi` file from a community/official repository (keyed by header name + content hash + target) instead of
parsing the header itself - falling back to an error ("get libclang, or a full build of cshiftc") only for a
header nobody has published a `.ffi` for yet. This composes naturally with the existing `.ffi` mechanism
(`using Name from "file.ffi";` already needs no libclang, see FFI.md) and with `cshc`'s own existing plan of
shipping/consuming `.ffi` files instead of parsing headers (section 1, "FFI (generating)"). Open questions for
when this is picked up: where such a repository would live and who curates/signs entries (a wrong `.ffi` file
silently produces a wrong ABI - the "errors in the header abort the import" safety net FFI.md describes does not
exist for a downloaded file); the `cshiftc build --offline`-style story when nothing is cached yet; and whether it
piggybacks on the existing `obj/ffi/` cache convention or introduces a separate one.

## Other open items (from earlier sessions)

- [x] The release workflow now gates the Linux job on the selfhost checks too (`CSHIFT_SKIP_SELFHOST=1` removed);
      release/v0.02 got a fully green Windows run first (both the regular archive and the new standalone
      executable - see section 5), which is what this was waiting on.
- [x] The Windows job's "Run tests" and "Test the assembled folder" steps, temporarily disabled while
      release.yml itself was being fixed, are back on (release/v0.02 confirmed both green before they were
      turned off).
- [ ] `demo/`: `libminifb.a` is not checked in (`demo/build-minifb.ps1` builds it); callbacks work, there are no lambdas yet.
- [ ] Language: lambdas/closures, interfaces as a value type, and a `List<T>` indexer are still open (see the README, "Known
      limitations").
