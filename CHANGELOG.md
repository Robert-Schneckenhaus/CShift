# Changelog

The changes that matter to users of CShift, newest first. A release's section is also the text of its
[GitHub release](https://github.com/Robert-Schneckenhaus/CShift/releases). New entries go under **Unreleased**; when a
release is made, that heading becomes the version (`## [0.19] - 2026-10-02`).

## [Unreleased]

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
