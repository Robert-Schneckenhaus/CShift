# Todo

Open work, most important first. What is done is described in the [documentation](docs/README.md); the history is in
the git log.

## Compiler

- [ ] When stage 0 has `Process.IsMacOS()` (0.32): use it in `selfhost/src/CodeGen/Runtime.csh`,
      `selfhost/src/Driver/Project.csh` and `selfhost/src/Driver/Serve.csh` instead of looking for
      `/System/Library/CoreServices/SystemVersion.plist`.
- [ ] Closures capture read-only copies. Capturing by reference (shared, mutable boxes, like C#) would need boxed
      locals; decide whether that is wanted.
- [ ] Sharing a container between threads: `Mutex<T>` and `SharedPtr<T>` need a `T` that can be copied between threads
      (values, strings, `ReadOnlySlice<T>` of them; no `List<T>`, arrays, `Dictionary`). A way to share a container
      safely (e.g. access only inside `Update`, with a check that nothing escapes) is open.
- [ ] Passing structs *by value* to a hand-written `extern "C"` (works through header imports, which generate C
      wrappers); implementing the C calling conventions in the compiler would remove the wrappers.
- [ ] m68k backend: faster counted loops, ending in jump towers. The runtime's `memcpy`/`memmove`/`memset` use towers
      already (a body unrolled 16 times, entered in the middle so that the first pass does the remainder, see
      [docs/amiga.md](docs/amiga.md#how-the-backend-works)). For the loops of a program they only pay off after the
      steps before them: today `for (var i = 0; i < row.Length; i += 1) row[i] = color;` runs about 20 instructions
      per element - the length is loaded twice (loop condition and bounds check), the index is shifted, `i + 1` is
      checked for overflow. In this order:
      1. keep loop-invariant values (`row.Length`, the array's data pointer) in registers,
      2. drop the bounds check when the loop condition already proves it (`0 <= i < a.Length`, `i` grows by 1, `a`
         is not assigned in the loop), and the overflow check of such an `i`,
      3. walk a pointer instead of indexing (`move.w %d4,(%a0)+`), with `dbra` for the count,
      4. then a tower for an innermost loop whose body is a few instructions without calls, at `-O2`/`-O3` only
         (`-O1` keeps the size small for floppy disks; on a 68020 the body must stay within its 256-byte cache).
         Bodies whose copies differ in size need a jump table instead of a computed offset.

## Tooling

- [ ] VS Code: renaming, and completion of names (not only of members after `.`), on top of the symbol index of
      `cshiftc query` (see [docs/semantic-pass.md](docs/semantic-pass.md)). Renaming needs a complete `--references`
      first: the index does not record where types, fields, enum members and constants are declared, nor the field
      names of initializers (`Point { X = 1 }`), so the references of `Point` and `X` miss those places.
- [ ] Errors with an end: cshiftc reports where an error starts, and the VS Code extension guesses how far the
      expression goes (`errorRangeEnd` in [vscode-extension/lib.js](vscode-extension/lib.js)). The parser would have
      to keep the end of every expression, and `cshiftc check` print it.
- [ ] Website (site/): a complete language reference (grammar, types, conversions, operators), separate from the
      tour.

## Standard library

- [ ] **UTF-8 on Windows:** `Main(string[] args)` gets the arguments in the ANSI code page (`NOVÁK` arrives as
      `4E 4F 56 C1 4B`, not UTF-8), and the file functions (`fopen`, `GetFileAttributesExA`, `MoveFileExA`, ...) take
      ANSI paths too, so a non-ASCII argument works as a path but is not UTF-8 text. Converting only the arguments
      would break such paths; the consistent fix is an application manifest with `activeCodePage` UTF-8 (Windows 10
      1903+), which makes argv and all `A` functions UTF-8 - it needs a resource compiler (`llvm-windres`) in the
      toolchain of the release. Until then the tests of the Ambermoon tools (`Tools/tests/run.sh` in the Ambermoon
      repository) leave out the cases with non-ASCII arguments on Windows.
- [ ] `System.Image`: GIF and JPEG decoding; a palette (and its PNG/BMP form) kept in `Image` for indexed images.
- [ ] More encodings (Latin-1, UTF-16) as new `EncodingKind`s.
- [ ] The rest of the byte functions on slices: `Encoding.GetString`, `string.FromBytes` and `FileStream.Read`
      (`Slice<uint8>`) still take arrays. `Regex` takes `string` (its matches refer to the text; a `StringSlice`
      needs matches with offsets into the slice).

## Ideas (not started)

- **`move` at the thread boundary.** `start Worker(move data)` hands a `List<T>`, an array or a `Dictionary` to a
  thread without copying it: `data` cannot be used after it (the same kind of check as for pattern variables that
  are not assigned), and at run time its block must have no other reference (a panic otherwise). For elements without
  references (numbers, structs of them) the outer block is enough; elements with references (`List<string>`) need
  every block checked, or a copy. The same model fits `Mutex<T>` with containers: the guard owns the value while the
  mutex is locked (as in Rust), see *Sharing a container between threads* above. One contextual keyword (like
  `start`), one rule and one check at run time; inside a thread the compiler's own moves (last uses, in-place appends)
  already need no syntax.
- **Packages beyond local folders.** `"dependencies"` names the folders of library projects
  ([docs/language/projects.md](docs/language/projects.md#libraries)); missing are versions, a place to publish and
  fetch packages (a registry, or git URLs with a tag), a lock file and a cache folder. A package stays source code,
  with prebuilt C libraries per platform where it needs them: the whole program is compiled at once and generics are
  instantiated per use, so there is no binary library format for CShift code.
- **A libclang-free `cshiftc` with a repository of pre-generated `.ffi` files** (keyed by header, content hash and
  target), falling back to an error for headers nobody has published. Open: who curates and signs the files (a
  wrong `.ffi` file silently produces a wrong ABI), offline builds, where the cache lives. Alternatives to libclang
  were investigated: syntax-only parsers (Tree-sitter's C grammar and similar) cannot expand macros or compute
  layouts; a real C front end is a project of its own (Zig's Aro).
- **A build written in CShift** (`build.csh`, like Zig), see [docs/build.md](docs/build.md).
- **lld instead of the clang driver** on Windows (smaller toolchain).
