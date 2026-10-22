# Todo

Open work, most important first. What is done is described in the [documentation](docs/README.md); the history is in
the git log.

## Compiler

- [ ] A warning for `.csh` files (the extension before 0.32), once most code has moved to `.cshift`; later, stop reading
      them.
- [ ] Closures capture read-only copies. Capturing by reference (shared, mutable boxes, like C#) would need boxed
      locals; decide whether that is wanted.
- [ ] Sharing a container between threads: `Mutex<T>` and `SharedPtr<T>` need a `T` that can be copied between threads
      (values, strings, `ReadOnlySlice<T>` of them; no `List<T>`, arrays, `Dictionary`). A way to share a container
      safely (e.g. access only inside `Update`, with a check that nothing escapes) is open.
- [ ] Passing structs *by value* to a hand-written `extern "C"` (works through header imports, which generate C
      wrappers); implementing the C calling conventions in the compiler would remove the wrappers.
- [ ] m68k backend, counted loops (see [docs/amiga.md](docs/amiga.md#how-the-backend-works)): a walk for `a[i + k]`,
      loops whose bound changes in the loop, invariant values computed once before the loop (`value + 1` is computed
      and checked in every round), and towers for bodies with a branch (a checked sum: the panic branch is never
      taken). The tower's table entry could be a computed offset where all copies have the same size.

## Tooling

- [ ] VS Code: completion of names (not only of members after `.`), on top of the symbol index of `cshiftc query`
      (see [docs/semantic-pass.md](docs/semantic-pass.md)). Renaming does not check yet whether the new name collides
      with another name in the same scope, nor rename the names of generic type parameters or of namespaces.
- [ ] Errors with an end: cshiftc reports where an error starts, and the VS Code extension guesses how far the
      expression goes (`errorRangeEnd` in [vscode-extension/lib.js](vscode-extension/lib.js)). The parser would have
      to keep the end of every expression, and `cshiftc check` print it.
- [ ] Website (site/): a complete language reference (grammar, types, conversions, operators), separate from the
      tour.

## Standard library

- [ ] **`System.Ui`, the next steps** ([docs/ui.md](docs/ui.md)), most useful first:
      - testing on real devices: phones (Android, iOS), Safari and Edge, pens; Playwright covers Chromium and Firefox
        (tests/ui-browser-check.mjs), the rest is untested;
      - the keyboard on phones and tablets: a canvas opens no on-screen keyboard, so text boxes cannot be typed into
        (a hidden `<input>` that gets the focus while a text box has it, and gives its text to the program);
      - the clipboard on Linux (X11 selections: `SelectionRequest` events answered by the window) and on AmigaOS
        (clipboard.device, IFF FTXT);
      - AmigaOS: faster images (an area of 320 x 192 full of 32 x 32 tiles takes about 1.2 s per frame in FS-UAE with
        the AROS ROM: planar bitmaps per image made once, drawn with the blitter, `BltMaskBitMapRastPort` for
        transparency), a blinking text cursor and the delay of tooltips (timer.device is in the wait already:
        `UiInput.Steady` turns them off for now), the shape of the mouse pointer, the dimming behind modal dialogs,
        a whole frame as an image (`Window.Show(image)`), AmigaOS 2.x (fixed pens, no `AllocBitMap`); none of it
        checked on a real Amiga with AmigaOS 3.x yet;
      - text from TrueType fonts (proportional, smooth): a rasterizer in CShift and a font with a free license embedded
        with `embed` (`ReadOnlySlice<uint8>`); the bitmap fonts stay for small targets;
      - repainting while Windows resizes the window (in its modal loop WM_PAINT shows the last frame; the new area
        stays empty until the drag ends), several windows, multi-line text boxes, input methods (dead keys and compose
        on X11: XIM);
      - in the browser: touch for GLFW programs (games still take mouse events only), the file chooser from the
        keyboard (Enter on "Choose file..." does not open it: browsers need a click there), folders on phones (no
        `webkitdirectory`).

- [ ] **`System.Audio`, the next steps** (0.38 has `AudioOutput` on Windows, Linux and in the browser):
      - checking on real machines: waveOut was tested under Wine only, and Firefox in the CI has no sound output (its
        AudioContext stays suspended, so tests/audio-browser-check.mjs checks only the writes there);
      - macOS (Core Audio, e.g. an AudioQueue) and AmigaOS (audio.device or Paula directly: 8-bit samples, a period
        per channel), both report no output for now;
      - float samples and more than 2 channels; a callback on a thread of its own for programs that need less than
        the 20 ms or so of a frame-driven refill.
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
- **A build written in CShift** (`build.cshift`, like Zig), see [docs/build.md](docs/build.md).
- **lld instead of the clang driver** on Windows (smaller toolchain).
- **Hot reload for `System.Ui` programs** ([docs/ui.md](docs/ui.md)). The state of the program lives in one struct
  (`App`), the UI is drawn every frame by `Draw(Ui ui, ref App app)`; `cshiftc run --hot` builds a small host (window, `Ui`, the `App` value, watches the
  sources like `cshiftc serve`) and the program's code as a shared library, and on a change loads the new library and
  calls its `Frame` from the next frame on - the window keeps its state. A failed build keeps the old code and shows
  the error in the window. Needs: a shared-library output (`type`), one runtime (ARC allocator) in the host for both;
  old libraries are never unloaded (`App` can hold string literals, `Action`/`Func` and interface values that point
  into them); a hash of `App`'s layout exported with `Frame` tells when the state has to be reset (or carried over
  through `System.Json`); globals of the library start fresh on every reload.
