# Todo

Open work, most important first. What is done is described in the [documentation](docs/README.md); the history is in
the git log.

## Compiler

- [ ] Closures capture read-only copies. Capturing by reference (shared, mutable boxes, like C#) would need boxed
      locals; decide whether that is wanted.
- [ ] Sharing a container between threads: `Mutex<T>` and `SharedPtr<T>` need a `T` that can be copied between threads
      (values, strings, `ReadOnlySlice<T>` of them; no `List<T>`, arrays, `Dictionary`). A way to share a container
      safely (e.g. access only inside `Update`, with a check that nothing escapes) is open.
- [ ] Passing structs *by value* to a hand-written `extern "C"` (works through header imports, which generate C
      wrappers); implementing the C calling conventions in the compiler would remove the wrappers.

## Tooling

- [ ] VS Code: renaming, and completion of names (not only of members after `.`), on top of the symbol index of
      `cshiftc query` (see [docs/semantic-pass.md](docs/semantic-pass.md)).

- [ ] Website (site/): a complete language reference (grammar, types, conversions, operators), separate from the
      tour.

## Standard library

- [ ] More encodings (Latin-1, UTF-16) as new `EncodingKind`s.

## Ideas (not started)

- **A libclang-free `cshiftc` with a repository of pre-generated `.ffi` files** (keyed by header, content hash and
  target), falling back to an error for headers nobody has published. Open: who curates and signs the files (a
  wrong `.ffi` file silently produces a wrong ABI), offline builds, where the cache lives. Alternatives to libclang
  were investigated: syntax-only parsers (Tree-sitter's C grammar and similar) cannot expand macros or compute
  layouts; a real C front end is a project of its own (Zig's Aro).
- **A build written in CShift** (`build.csh`, like Zig), see [docs/build.md](docs/build.md).
- **lld instead of the clang driver** on Windows (smaller toolchain).


## New ideas

- ReadOnlySlice<string[]> embed_lines("file.txt")
- Implicit conversion from StringSlice to ReadOnlySlice<char>?
- Wrong part is marked as error sometimes. E.g. if `Bar` has return type `int` and `foo` is a `char[]`, then `foo[i] = Bar(foo[i]);` should mark `Bar` as an error as a cast to `int` is missing. Or mark the spot in front of `Bar`. Currently the VSCode extension highlights the parameter `foo[i]` but says
  "cannot implicitly convert 'int32' to 'uint8' (an explicit cast is required)"
  I saw similar things in other places as well.
- Add things like `bool Equals(StringSlice a, StringSlice b)`, so all the good stuff available for `string` should also be available for `StringSlice`. Also prefer `StringSlice` in the stdlib, as `string` can be converted to it for free. For example `File.Exists` or `File.Delete` should use string slices to allow modified strings as input.
- Jump Tower support for Amiga
- Something similar to nuget packages. For the start maybe only local packages. Library projects can be published as packages. They can contain the library files for specific or all targets.
