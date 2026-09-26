# Todo

Open work, most important first. What is done is described in the [documentation](docs/README.md); the history is in
the git log.

## Compiler

- [ ] **A separate semantic pass** (postponed on purpose). Today checking and code generation are one walk over the
      syntax tree, and the compiler stops at the first error (`Fail`). A pass that resolves names and types first
      would allow several errors per run, checking generic bodies without instantiating them, better inference
      (type arguments from lambdas, `var f = x => ...` with written parameter types), and tools (hover, go to
      definition). Large: it touches every part of `selfhost/src/CodeGen`.
- [ ] Generic type arguments are not inferred from lambdas (`list.Select<string>(x => ...)` needs the `<string>`).
- [ ] Closures capture read-only copies. Capturing by reference (shared, mutable boxes, like C#) would need boxed
      locals; decide whether that is wanted.
- [ ] `Mutex<T>` and `SharedPtr<T>` for containers: `T` must be copyable between threads today (no `List<T>`,
      arrays). A way to share a container safely (e.g. access only inside `Update`, with a check that nothing
      escapes) is open.
- [ ] Debug information (DWARF/PDB).
- [ ] Passing structs *by value* to a hand-written `extern "C"` (works through header imports, which generate C
      wrappers); implementing the C calling conventions in the compiler would remove the wrappers.

## Bootstrap and releases

- [ ] The Windows paths of the self-hosted compiler (`selfhost/native/host.c`: `LoadLibraryA`, `GetModuleFileNameA`;
      the native `Directory` functions on MinGW) are only exercised by the release workflow; run it on a release
      branch before the first self-hosted release.
- [ ] Linux standalone executable: still needs the host's glibc and binutils (`build-essential`), like the regular
      Linux archive; only Windows is zero-dependency.
- [ ] The toolchain cache of the standalone executable is never cleaned up (`cshiftc --clear-cache`?).

## Standard library

- [ ] Streams, `Stack`/`Queue`, date and time, number formatting options (`ToString("F2")`), more encodings.
- [ ] `Directory`: deleting, moving; `File`: moving, timestamps.

## Ideas (not started)

- **A libclang-free `cshiftc` with a repository of pre-generated `.ffi` files** (keyed by header, content hash and
  target), falling back to an error for headers nobody has published. Open: who curates and signs the files (a
  wrong `.ffi` file silently produces a wrong ABI), offline builds, where the cache lives. Alternatives to libclang
  were investigated: syntax-only parsers (Tree-sitter's C grammar and similar) cannot expand macros or compute
  layouts; a real C front end is a project of its own (Zig's Aro).
- **A build written in CShift** (`build.csh`, like Zig), see [docs/build.md](docs/build.md).
- **lld instead of the clang driver** on Windows (smaller toolchain).
