# Changelog

The changes that matter to users of CShift, newest first. A release's section is also the text of its
[GitHub release](https://github.com/Robert-Schneckenhaus/CShift/releases). New entries go under **Unreleased**; when a
release is made, that heading becomes the version (`## [0.19] - 2026-10-02`).

## [Unreleased]

### Language
- **Changed:** calling a method that changes the struct on a `const ref` parameter (or on a field of one, or on a
  variable that a lambda uses) is a compile error instead of working on a copy that is thrown away. The message says
  what the method does ("it assigns 'Count'", "it calls 'Bump', which assigns 'Count'"); call it on a copy or make the
  parameter `ref`. Methods that only change what a field refers to - `Items.Add(x)`, `Items[i] = x` on a `List` field -
  are allowed, and `x[k] = v` on a `const ref` struct now works when its `Set` does not change the struct (before it
  was always an error). `cshiftc check` and the VS Code extension show the error as well.

### Standard library
- `Console.ReadLine()` reads a line of the standard input (`Optional<string>`, without the line break; `null` at the
  end of the input). What was written with `Console.Write` before is shown first, so `Console.Write("Name: ")` works
  as a prompt. On every target: Linux, macOS, Windows, WebAssembly (WASI) and AmigaOS.

### Compiler
- **Fixed:** a branch of `?:` whose value is converted to the type of the other branch with a temporary (an array to
  a `ReadOnlySlice`, as in `ReadOnlySlice<string> names = n < 3 ? new string[0] : args[2..];`) generated invalid
  code that clang could not compile (it crashed): the temporary was released after the branches, also when it was
  not made.
- Fewer copies, and the compiler compiles itself with 20 % fewer instructions: `list.Get(i).Name` (and
  `list[i].Name`) reads the field where the element is instead of copying the whole element with all its references
  first, and a local variable that copies a part of a `const ref` parameter (`var tree = cg.Tree;`) and is only read
  afterwards is an alias of it instead of a copy.

### Tools
- [Ambermoon/](Ambermoon/README.md): ports of command line tools of the Amiga game
  [Ambermoon](https://github.com/Pyrdacor/Ambermoon) and of the libraries they need: `AmbermoonPack` (packs and unpacks
  the game's file formats, 60 to 300 times faster than the original), `AmbermoonEventEditor` (edits the events of
  maps and characters), `HexValueChanger`, the text pack tools of translations (`AmbermoonIntroTextPacker`,
  `AmbermoonExtroTextPacker`, `AmbermoonExtroIntroTextPackCreator`), `AmbermoonDiskExtract` (the files of the ADF disk
  images), `AmbermoonListExtractor` and the labyrinth tools (`AmbermoonLabdataEditor`, `AmbermoonLabdataExtractor`,
  `AmbermoonUsedColorsDetector`, `Ambermoon3DMapViewer`), `AmbermoonMonsterEditor`, `AmbermoonItemEditor` and
  `AmbermoonNameExtract`. Their results are those of the original tools (`Ambermoon/tests/run.sh`, part of
  `tests/run_tests.sh`).
- Building the compiler from source starts from cshiftc 0.26 instead of 0.09 (`selfhost/stage0.txt`, downloaded by
  `selfhost/fetch-stage0.sh`): the compiler's own sources may use the language and the standard library of 0.26.

## [0.26] - 2026-10-06

### Language
- A `string` or `StringSlice` converts to `ReadOnlySlice<char>` without a copy, so code for slices of characters
  takes text (a `string` argument still prefers a `StringSlice` parameter); never back, the characters need not be
  UTF-8. `text.AsBytes()` is the same view as `ReadOnlySlice<uint8>`, for functions that take bytes.
- `embed_lines("file")`: the lines of a file as a `const ReadOnlySlice<string>`, read when the program is compiled -
  without their line ends (`\n` or `\r\n`), without an empty line after the last line end
  ([constants](docs/language/constants-and-globals.md#embedded-files-embed-embed_filenames-and-embed_lines)).

### Compiler
- The compiler is about three times as fast: its functions take the compiler's state as `const ref Compiler` instead of
  a copy, which counted the references of its 37 fields up and down at every call. Generating the IR of the compiler
  itself takes 0.9 s instead of 3.0 s (69 % fewer instructions); `cshiftc check` and the VS Code extension profit as
  well.
- Appending to a string is in place when nothing else refers to it: `text += ...` and `text = text + a + b` on a local
  variable, and the pieces of `a + b + c`. The block grows with `realloc`, with room to spare, so a loop of appends
  takes linear time instead of quadratic (80,000 lines: 0.016 s instead of 8.1 s). A shared string - a copy, a slice,
  a parameter the caller holds - is copied first, as before.
- The last use of a local variable hands its reference on instead of counting it up now and down at the end of the
  scope: `return list;`, `var b = a;` and `b = a;` when `a` is not read again, and the fields and items of
  `return Foo { Items = items }` and `return [a, b]`. Which use is the last one is decided from the code (not inside
  loops that reach it again, not when the variable's address is taken). In the compiler's own code 9 % of the retains
  go away; on the 68000 a loop that builds and returns structs of a string and a list takes 13 % fewer cycles (on x86
  LLVM had removed most of these pairs already).
- A method that replaces a field of the copy it works on - called on a `const ref` parameter or on a temporary such
  as `Make().Rename()`, of a struct or a union - no longer frees the old value twice (the caller still held it) and no
  longer leaks the new one: the copy is released with what it holds after the call.
- A method called on a `const ref` parameter (or on a field of one) no longer works on a copy when it does not change
  `this`: the compiler decides from the method's body whether it assigns to a field, passes one with `ref` or takes
  its address, or calls such a method on one. The methods of `List`, `Dictionary`, `StringBuilder` and the other
  containers, for example, run on the caller's value without counting its references up and down.
- A new string's block is no longer filled with zeros first (`malloc` instead of `calloc`): its text is copied in right
  after, only the 0 byte behind it is written. Arrays, lists and objects are still zeroed.

### Amiga
- `memcpy`, `memmove` and `memset` of the Amiga runtime use jump towers (an unrolled move that the loop enters in the
  middle) and longs where the addresses allow: copying 64 KB takes about 6 cycles per byte instead of 44 (15 when only
  one address is odd), filling 3.4 instead of 38. `Array.Copy`, list growth and string operations profit.
  `memmove` backwards no longer copies byte by byte.
- `tests/run_tests.sh` runs an AmigaOS test program of the runtime with vamos (amitools) when it is installed.
- `Bitmap.DrawPattern` and `Sprite.Create` also take the rows as a `ReadOnlySlice<string>`, such as the lines of a
  file from `embed_lines`; demo-amiga-gfx uses that instead of splitting the text at run time.

### Standard library
- `StringSlice` can do what `string` can: `Equals`, `GetHashCode` (the same hash as a string with the same text) and
  `CompareTo`, so slices are keys of a `Dictionary`, elements of a `HashSet` and sorted in a `List`; `+` joins two
  slices; `slice.CStr()` (`unsafe`) passes one to C, copied only if it does not reach the end of its string.
- Paths, names and commands are `StringSlice` parameters: `File`, `Directory`, `Path`, `FileStream`/`StreamReader`/
  `StreamWriter`, `Process.Run`/`RunCapture`/`GetEnv`, and the text of `File.WriteAllText` and `Encoding.GetBytes`.
  `File.Exists(line.Trim())` works without `.ToString()`; strings are passed as before, without a copy.
- `FileStream.Write` and `File.WriteAllBytes` take a `ReadOnlySlice<uint8>`: an array, a part of one, or
  `text.AsBytes()`.
- **Changed:** `List`, `Dictionary`, `HashSet`, `Stack`, `Queue` and `StringBuilder` no longer make their storage on
  the first `Add`. The zero value - `new List<T>()`, `new()`, a field that was not given a value - is an empty
  container that can be read (`Count()` is 0, `foreach` runs no turn) but not changed: `Add`, `Set`, `Append`, `Push`
  and `Enqueue` panic and say so. Create them with `Create()` or `[]`; `IsCreated()` tells the two apart. Before, such a
  container was not connected to its copies until something was added, and an `Add` on a copy (a `const ref`
  parameter) could get lost.
- `StringBuilder` copies its text with `Array.Copy` when it grows instead of byte by byte, and
  `Encoding.UTF8().GetBytes` copies with `memcpy`. A loop that builds text with a `StringBuilder` runs 37 % fewer
  instructions; the compiler, which writes its output that way, 5.6 % (with the change above).

### Tools
- Libraries: a project with `"type": "library"` is source code that other projects use; `"dependencies":
  ["../geometry"]` in `cshift.json` makes its sources, `links`, include paths, defines and `ffiApi` (with its
  `platforms` entries, e.g. prebuilt C libraries per platform) a part of the project. Libraries may depend on
  libraries; one that is reached twice is used once, a cycle is an error. `cshiftc build` of a library checks it
  ([projects](docs/language/projects.md#libraries)).
- Errors point at the right place: a value that does not convert at its start (`foo[i] = Bar(foo[i]);` at `Bar`, not
  at the `(` before the argument), a call that does not resolve (no such function, no matching overload, a missing
  method) at the name of the function, a missing member at its name instead of the `.` before it.
- VS Code: an error underlines the expression it is about (`Bar(foo[i])`), not everything from there to the end of the
  line; at a keyword or a declaration it is still the rest of the line.

## [0.25] - 2026-10-03

### Amiga
- `Bitmap.DrawPattern` takes the rows as a `ReadOnlySlice<StringSlice>` (parts of a text, not copied), and a new
  overload draws bytes: `DrawPattern(x, y, width, pattern)` with one color per byte of a `ReadOnlySlice<uint8>`, row
  after row; a value of 32 or more leaves the pixel as it is. demo-amiga-gfx draws its ball and ship from text files.

## [0.24] - 2026-10-03

### Website
- A playground (/playground/): the compiler runs as WebAssembly in the browser and checks the program as you type,
  shows what the name at the cursor is (the hover of the VS Code extension) and the LLVM IR it generates; examples, and
  a link that carries the program. The website build compiles it (site/scripts/playground.sh).
- The playground runs programs: **Run** (Ctrl+Enter) compiles with the wasm backend and runs the program in the
  browser, with its output below the editor.

### Targets
- A WebAssembly backend of its own: `--backend wasm` (or `"backend": "wasm"`) writes a `.wasm` module for WASI without
  clang, wasi-libc or a linker, with a C library written in CShift (stdlib/wasm); functions without a body are imported
  from the module `env` (with a warning). The compiler builds itself with it in seconds, and that compiler (as
  WebAssembly) builds itself again byte for byte; the CI runs all tests with it ([docs/wasm.md](docs/wasm.md)).
- WebAssembly: `--target wasm32-wasi` (or `"target": "wasm32-wasi"`) compiles a program to a `.wasm` file for node,
  wasmtime and other WASI runtimes, with clang, wasi-libc and wasm-ld ([docs/wasm.md](docs/wasm.md)). The standard
  library runs unchanged except where the platform has nothing: `start` (threads) is a compile error, `Process.Run`
  cannot start programs, the local time is UTC. `CSHIFT_TARGET=wasm32-wasi bash tests/run_tests.sh` runs the tests
  with node; the CI does it on Linux.
- `CSHIFT_WASI_SYSROOT` names the sysroot of WASI (e.g. of wasi-sdk) when clang does not find it.
- WebAssembly programs get 8 MB of stack (like the main thread on Linux) instead of wasm-ld's 64 KB, which deep
  recursion overflowed into the heap.

### Language
- An `extern "C"` declaration and a definition (`extern "C"` with a body) of the same C function are one function
  (a call is no longer ambiguous): the definition is called.

## [0.23] - 2026-10-02

### Language
- A name can be declared only once in a block: a second local variable, local constant or pattern variable with the
  same name in the same block, and two parameters with the same name, are compile errors (the second declaration
  used to hide the first). An inner block may still reuse the name of an outer one.
- `...` (a variable argument list) is only allowed in the declaration of a C function (`extern "C"` without a body);
  a CShift function with `...` used to produce invalid code instead of an error.

### Documentation
- The language reference ([docs/spec](docs/spec/README.md), on the website under "Language reference") gives the
  precise rules of the language - lexical structure, programs and names, types and conversions, declarations,
  expressions, statements, memory, run time - and the complete grammar in EBNF.
- The language guide shows `//!` (the doc comment of a namespace) next to the other comments, with an example in the
  chapter on doc comments.
- Doc comments: `Environment.Panic` exits with code 101 (not 1); `char` and `uint8` are separate types that convert
  implicitly to each other.

## [0.22] - 2026-10-02

### Website
- The documentation as a website with search (https://robert-schneckenhaus.github.io/CShift/): the language guide,
  the topics, and the reference of the standard library and the built-in types, made from their doc comments, with
  the release that added each declaration ("since", computed from the libraries of all earlier releases). Every
  release publishes it; there is one version per major release (/CShift/v0/, ...) with a switch between them
  (site/, .github/workflows/pages.yml).

### Language
- Doc comments: `///` documents the declaration after it, `//!` the namespace of the file. The text is Markdown with
  links to declarations (`[List<T>.Add]`) and tags (`@param`, `@returns`, `@error`, `@panics`, `@since`,
  `@deprecated`, `@see`, `@internal`) ([docs/language/doc-comments.md](docs/language/doc-comments.md)).

### Tools
- `cshiftc doc` writes the documentation of the standard library (or of a program) as JSON and checks the doc
  comments: unknown tags, `@param` names, links and `@error` values; `--require-docs` also wants a comment on every
  public declaration.
- VS Code: the hover shows the doc comment of a declaration.

### Standard library
- The built-in types and functions (`string`, the numbers, arrays, slices, `Optional`, `Error`, `Console`,
  `Environment`, `Memory`, `Thread`, `SharedPtr`, `Enum<T>`, `Action`, `Func`) are declared with doc comments in
  `stdlib/builtin`: `cshiftc doc` documents them, and the hover shows their comments too.
- Every public declaration has a doc comment (also the AmigaOS graphics and hardware), so the hover in VS Code
  explains the functions, their parameters, results, errors and panics; `cshiftc doc` writes the reference.

## [0.21] - 2026-10-02

### Tools
- Debug information: `-g` (or `"debug": true` in `cshift.json`) lets gdb and lldb stop on lines and functions, step
  through the program, show the call stack with files and lines and print parameters, local and global variables
  with their types ([docs/debugging.md](docs/debugging.md)).
- Pretty printers for gdb and lldb (`tools/debug`): strings as text, arrays, slices, `List`, `Dictionary`, `HashSet`,
  `Stack`, `Queue`, `StringBuilder`, `Optional`, `SharedPtr` and unions by their contents. Programs built with `-g`
  carry the gdb printers themselves.
- VS Code: **F5** debugs the program of a `.csh` file (built with `-g -O0`, run under lldb through the CodeLLDB
  extension): breakpoints, stepping, the call stack and the variables with the pretty printers; launch configurations
  of the type `cshift`.

### Language
- A `ReadOnlySlice<T>` can be a parameter of a `thread` function (and the value of a `Mutex<T>`) when its elements
  can: the thread gets its own copy of the elements, like a string. So `start Sum(numbers)` works with an `int[]`.

### Standard library
- JSON: `Json.Parse` and `JsonValue` (build, read and write JSON; objects keep the order of their keys).
- Regular expressions: `Regex` (groups and named groups, sets, anchors, word boundaries, lazy and counted repetition,
  `(?i)`/`(?m)`, UTF-8) with `IsMatch`, `Match`, `Matches`, `Replace` (`$1`, `${name}`) and `Split`; a search is
  linear in the pattern size times the text length.

### Compiler
- A struct can contain a `Dictionary` (and other collections) of itself: a struct reached through an array is no longer
  taken for one contained by value.
- Smaller programs: `Console.Write`, panics, error messages and the integer `ToString` no longer go through `printf`
  (they write with `fwrite` and convert numbers themselves).
- AmigaOS: an executable contains only what it uses, also of the startup code and the runtime (they are taken in
  pieces). `printf`'s formatting is only in programs that call `printf` or format floating point numbers. Hello world
  shrinks from 71 KB to 8 KB, demo-amiga-hw from 89 KB to 28 KB, demo-amiga-gfx from 137 KB to 76 KB.

## [0.20] - 2026-10-01

### Amiga
- `Amiga.Screen`, `Bitmap`, `Sprite`, `CopperList`, `Blitter`, `SystemFont` (`stdlib/amiga/graphics.csh`): screens with
  double buffering and their own copper instructions, bitmaps in chip memory, the blitter (clear, fill, copy, bobs with
  a mask), lines, pixels, text in the system font, hardware sprites.
- demo-amiga-gfx: bouncing balls with the blitter, a sprite and a copper sky at 50 frames per second on an A500.

### m68k backend
- Loads and stores at constant addresses (custom chip registers) are one instruction; checked additions of constants
  are folded; multiplications without overflow check use shifts or `muls.w`; the code that ends the program on an
  error is moved to the end of a function, so the normal path runs without branches.

### Tools
- VS Code: find all references, the outline of a file (structs with their members, functions, enums, constants), and
  completion after `.` (fields, methods, enum members, static methods, string functions); `cshiftc query --references`,
  `--members` and `--outline <file>`.

### Compiler
- Casts between integers and pointers go through an integer as wide as a pointer of the target (also on 32-bit targets);
  unsigned values are zero-extended.
- More errors are reported in one run (by the semantic pass instead of code generation): pointers outside `unsafe`,
  constant indexes out of the range of a `Fixed<T, N>`, `using` without `IDisposable`, union members in `is`, `switch`
  over error codes, function names and lambdas converted to `Action`/`Func` (signature, parameters, `ref` parameters,
  `thread` functions), calls through function values, variables changed in a lambda, interface parameters in a lambda,
  `var` with a lambda, the binding of `is not`.
- Generic bodies: a value of a type parameter offers only the methods of its constraints (and `ToString`); calling
  another one is an error, also if the generic function is never used.

## [0.19] - 2026-10-01

### Standard library
- `DateTime`, `TimeSpan`, `DayOfWeek` and `Stopwatch`: the clock and time zone, calendar arithmetic, formatting
  (`ToString("yyyy-MM-dd HH:mm")`, ISO 8601) and parsing; `Thread.Sleep`.
- Streams: `FileStream` (reading and writing in pieces, seeking), `StreamReader` (`ReadLine`), `StreamWriter`.
- `File.Move`, `File.GetLastWriteTime`/`GetLastWriteTimeUtc`, `Directory.Delete` (also recursive), `Directory.Move`;
  `IoError.CannotMove`.
- An operating system layer (`stdlib/os/`) that the compiler picks for the target (Windows, POSIX, AmigaOS).

## [0.18] - 2026-10-01

### m68k backend
- Division by powers of two uses shifts instead of `divs`/`divu` (signed division still rounds towards zero).
- The bounds check needs fewer instructions to get the length of a string or array.
- The optimization level controls inlining: `-O0` inlines nothing, `-O1` only functions that are not larger than their
  call (smaller programs), `-O2`/`-O3` also larger functions in loops.
- demo-amiga-hw: about 122,000 cycles per frame (was 129,000).

## [0.17] - 2026-10-01

### Language
- `new { ... }` and `new()` take their type from wherever it is known: declarations, assignments, return values,
  arguments (when all overloads agree on the parameter), fields of an initializer, `Optional<T>`/`Error<T>`.

### Tools
- `cshiftc --clear-cache` deletes the toolchains a standalone cshiftc has unpacked.

## [0.16] - 2026-09-30

### Language
- `unsafe` on a whole function or method (`unsafe void Render() { ... }`) and before a single statement
  (`unsafe Memory.Free(p);`).
- `Player p = new { X = 1 };` and `Player p = new();` in declarations with a type.

### Tools
- `cshiftc new` names the compiler as it was started (`cshiftc run`) in its hint.

## [0.15] - 2026-09-30

### Amiga
- A second backend, CShift's own 68000 code generator, assembler and linker: `--target m68k-amigaos` builds AmigaOS
  executables (68000, AmigaOS 1.3 and later) without LLVM or an Amiga toolchain; `--backend`, `--emit-asm`.
- AmigaOS libraries from the NDK's SFD files: `using Gfx from "graphics_lib.sfd";` (register calls, libraries opened
  at startup); `--ndk`, `"ndk"` in cshift.json, `CSHIFT_NDK`.
- `Amiga.Hardware`: take over the machine, copper, vertical blank, chip memory.
- A C library on exec/dos, soft float and math functions for the 68000.
- Demos: demo-amiga-hw (copper raster bars, 50 frames per second on an A500) and demo-amiga-ndk (a rotating cube in an
  Intuition window).

### Standard library
- `FastTrig`: sine, cosine, tangent and atan2 from tables, with integer angles and fixed point results.
- `Memory.VolatileRead` / `Memory.VolatileWrite`.

### Compiler
- 32-bit targets: the pointer size comes from the target triple.

## [0.14] - 2026-09-29

### Tools
- Hover and go to definition for namespaces, function pointer fields of C structs and lines of C headers.

### Language
- `void*` converts to C function pointers.

## [0.13] - 2026-09-29

### Tools
- Hover shows built-in functions, declarations and the declared types in generic bodies.

## [0.12] - 2026-09-29

### Language
- Integer arithmetic in the target type: `uint8 r = a + 1;` without a cast (also in arguments and `?:` branches).
- `--unchecked` / `"unchecked": true`: integer overflow wraps around; `--checked` overrides it.

## [0.11] - 2026-09-28

### Tools
- VS Code integration: `cshiftc check` and `cshiftc query`; the extension shows the errors of the program, hover and
  go to definition.

## [0.10] - 2026-09-28

### Compiler
- One run reports several errors (up to 50): a semantic pass checks declarations, function bodies, global initializers
  and constants before code generation; generic bodies are checked once, type arguments are inferred from lambdas.

### Standard library
- Number formats: `ToString("F2")`, `$"{x,8:F2}"`.

### Other
- CShift is released under the MIT license.

## [0.09] - 2026-09-27

### Standard library
- `Stack<T>`, `Queue<T>`.

### Language
- `embed("*.txt")` and `embed_filenames("*.txt")`: the contents and names of all matching files.
- Panics show where they happened (`file:line:column in Function`).

## [0.08] - 2026-09-27

### Language
- `Fixed<T, N>`: fixed-size arrays stored inline.
- Collection expressions as `Optional<T>` and `Error<T>`.

## [0.07] - 2026-09-26

### Language
- `embed("file")`: a file's exact content as a string constant.
- `ReadOnlySlice<T>`, constant slices, `Enum<T>.Count/Min/Max/Values/Names`.

## [0.06] - 2026-09-26

### Language
- Collection expressions: `[a, b, ..c]` as arrays, slices, `List<T>`, `HashSet<T>`, ...

### Standard library
- String helpers work on slices.

## [0.05] - 2026-09-26

### Language
- Slices: `a[i..j]`, `a[^n]`, `Slice<T>`, `StringSlice`.
- Exhaustive `switch` over enums, unions and error codes; enums as text are the names of their members.

### Standard library
- Typed errors.

## [0.04] - 2026-09-26

The first release of the self-hosted compiler (cshiftc written in CShift).

### Language
- Lambdas and closures, string interpolation, `ToString()` for structs.
- Interface values; interfaces as `ref`/`const ref` parameters without boxing.
- Sum types: `union Shape : IShape { Circle, Rect }`.
- Error enums and typed results `Error<T, E>`; `is error e`, `is not`, `is null`.
- `Mutex<T>`; strings are copied into threads.
- `List<T>`: `ForEach`, `Where`, `Select`, `Any`, `All`, `FindIndex`.

## [0.03] - 2026-09-25

- Release builds are tested on Linux and Windows.

## [0.02] - 2026-09-25

- Threads: `thread` functions, `start`, `Thread`/`Thread<T>`, `SharedPtr<T>`.
- A standalone, self-extracting single-file executable.

## [0.01] - 2026-09-22

The first release (compiler written in C++ against LLVM).

- The language: structs, generics, interfaces, `Error<T>`/`Optional<T>`, ARC, enums, global variables, constants.
- Standard library: `List`, `Dictionary`, `File`, `Encoding`, `Math`, string helpers.
- Projects (`cshift.json`, `cshiftc new/build/run`), C header import, function pointers.
- VS Code extension with syntax highlighting and snippets.
