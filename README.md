# CShift

CShift is a native, C#-like systems language (see [LanguageDesign.md](LanguageDesign.md)):
structs instead of classes, no GC (ARC), no headers, generics via monomorphization, direct C FFI.

This repository contains the first compiler, `cshiftc`, written in C++17 with LLVM as its back end.

```
source (.csh) ─▶ lexer ─▶ parser ─▶ AST ─▶ type checking + codegen ─▶ LLVM IR ─▶ optimization ─▶ .obj ─▶ clang (linker) ─▶ .exe
```

```csharp
using System;

struct Vec2
{
    float X;
    float Y;

    float Length() { return sqrt(X * X + Y * Y); }
}

Error<int> Parse(string text) { /* ... */ }

int Main()
{
    var v = Vec2 { X = 3, Y = 4 };
    Console.WriteLine(v.Length());   // 5
    return 0;
}
```

For a guided tour of the language with more examples, see **[docs/language/README.md](docs/language/README.md)**.

## Ready-made releases

Every release has an archive for **Windows (x64)** and **Linux (Ubuntu, x64)** on the
[releases page](https://github.com/Robert-Schneckenhaus/CShift/releases). It contains everything you need: the
compiler and a matching toolchain (clang, libclang, and on Windows also lld plus the MinGW-w64 headers and
libraries).

```
Windows:  cshift-1.05-windows-x64.zip       unpack it, add the folder to PATH
Linux:    cshift-1.05-linux-x64.tar.xz      tar -xf ... -C ~ ; add to PATH; sudo apt install build-essential
```

```
cshiftc --version
cshiftc new hello
cshiftc run hello
```

`cshiftc` first looks for clang in a `toolchain` folder next to itself; an existing LLVM/MSYS2 installation is then
not needed. On Linux, the C library and linker come from the system (`build-essential`).

**Publishing a release:** push a `release/vX.XX` branch (e.g. `release/v1.05` → version `1.05`, tag `v1.05`). The
workflow [.github/workflows/release.yml](.github/workflows/release.yml) builds the compiler for both platforms, runs
the tests (including once more against the fully assembled archive), and publishes the release. Pushing to the same
branch again replaces the release. The branch has to contain the workflow file, so branch off from a commit at or
after this one. The archives themselves are built by [packaging/](packaging/).

## Building it

Requirements: a C++17 compiler, CMake ≥ 3.20, the **LLVM development packages** (headers + libraries; tested with
LLVM 22.1.8), and `clang` to link the generated programs.

### Windows (recommended: MSYS2)

Visual Studio doesn't come with the LLVM libraries needed to program against the LLVM API; MSYS2 does:

```powershell
winget install MSYS2.MSYS2
# Once, in the "MSYS2 CLANG64" shell:
pacman -S --needed mingw-w64-clang-x86_64-clang mingw-w64-clang-x86_64-llvm `
                   mingw-w64-clang-x86_64-cmake mingw-w64-clang-x86_64-ninja

.\build.ps1          # builds into .\build\cshiftc.exe
.\build.ps1 -Test    # builds and runs the tests
```

By default, `build.ps1` builds `cshiftc.exe` **statically** (`-DCSHIFT_STATIC=ON`, about 120 MB): the exe starts from
any shell, without needing the MSYS2 DLLs on `PATH`. To compile programs it needs `clang` as the linker; if it's not
on `PATH`, `C:\msys64\clang64\bin` (or `%MSYS2_ROOT%\clang64\bin`) is tried automatically, otherwise `--cc <path>`
helps. `.\build.ps1 -Dynamic` produces the smaller DLL-based build, which only starts with `C:\msys64\clang64\bin` on
`PATH` (if it doesn't find it, Windows aborts silently).

### Linux / macOS

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release   # add -DLLVM_DIR=<llvm>/lib/cmake/llvm if needed
cmake --build build
tests/run_tests.sh
```

## VS Code

The `vscode-extension/` folder has an extension for `.csh` files (syntax highlighting, snippets,
brackets/comments) — see [vscode-extension/README.md](vscode-extension/README.md) for installation.

## Usage

```
cshiftc [options] file.csh [more.csh ...]

  -o <file>          output file
  -c                 generate an object file only (no linking)
  --emit-llvm        output LLVM IR (.ll) instead of a program
  -O0 .. -O3         optimization level (default -O2)
  --target <triple>  target platform (default: host)
  --cc <program>     linker driver (default: clang)
  -l<name>           link an additional library
  -L<dir>            linker search path
  -I<dir>            search path for C headers (using X from "header.h")
  -D<name>[=value]   macro used when parsing C headers
  --ffi-api=<text>   headers with this path fragment belong to the imported API (umbrella headers)
  file.a, file.o     libraries/object files are linked in
  --run              run the program after building it
  --arc-stats        debug: print the number of heap allocations/frees when the program ends
  --version          print the version
```

All the files passed to it (or the sources of a project) form one program; types and functions can be defined in any
order and in any file (no forward declarations needed).

```
cshiftc tests/test.csh tests/mathlib.csh -o test.exe --run
```

Errors are printed in the form `file:line:column: error: text`.

## Projects

Larger programs are described with a `cshift.json` (name, sources, output, optimization, libraries); the design and
a look ahead (a Zig-like `build.csh`) are in [BuildDesign.md](BuildDesign.md).

```
cshiftc new hello       # a new project: hello/cshift.json, hello/src/main.csh
cshiftc run hello       # build and run (without an argument: cshift.json in the current folder or a parent)
cshiftc build           # build only  ->  bin/<name>[.exe]
```

```json
{
	"name": "demo",
	"sources": ["src"],
	"output": "bin/demo",
	"optimize": 2,
	"links": []
}
```

A finished example is in [demo/](demo/): a MiniFB window with animated plasma (C header import and callbacks, with
VS Code tasks).

C libraries are imported without hand-written declarations: `using Zlib from "zlib.h";` imports the header as a
namespace (see [FFI.md](FFI.md)); `includePaths`, `defines`, `libraryPaths` and `links` (files like `libminifb.a`
too) go in `cshift.json`.

## Language status

Implemented from the design:

| Area | Status |
|---|---|
| Namespaces (`namespace A.B;`), `using`, multiple files, global symbol resolution | ✔ |
| Global variables (zero value or an initializer, running before `Main`) | ✔ |
| Structs (value semantics), initializers, `new T()`, methods, `static` methods, nested structs | ✔ |
| Visibility via a `_` prefix (private) for fields and methods | ✔ |
| Struct inheritance (one base, the base comes first in the layout), upcasting, hiding methods | ✔ |
| Interfaces (methods), several per struct, checking the implementation | ✔ (static only, see below) |
| Generics: structs and functions, monomorphization, type inference, explicit type arguments | ✔ |
| Constraints (`where T : IComparable<T>`), checked at compile time | ✔ |
| Enums with a mandatory base type and explicit values | ✔ |
| ARC for strings and arrays (reference semantics, `Clone()`), including inside structs/`Error`/`Optional` | ✔ |
| Strings: UTF-8, immutable, `+`, `==`, `[i]`, `Length`, `Substring`, `CStr()` | ✔ |
| `Error<T>` / `Optional<T>`, bool semantics, `is T x`, `switch` patterns, `try`, no nesting allowed | ✔ |
| `IDisposable` + `using` (declaration and block form; also on `return`/`break`/`continue`/`try`) | ✔ |
| `ref` / `const ref` (value, read-only alias, alias) | ✔ |
| Primitive types with aliases (`int`=`int32`, …), `bool`, `char` (= `uint8`), `nint`/`nuint` (pointer-sized) | ✔ |
| Checked integer arithmetic (overflow, division by zero, array/string bounds → panic), `unchecked` | ✔ |
| Operators and precedence like C# (without `++`/`--`), `?:`, casts, `sizeof` | ✔ |
| `if`/`while`/`do`/`for`/`foreach` (arrays, strings)/`switch`/`break`/`continue`/`return` | ✔ |
| Function overloading | ✔ |
| C FFI: `extern "C"`, variadic functions (`printf`), `link "lib"`, pointers | ✔ |
| Function pointers `Action<…>`/`Func<…,R>` (function names, no closures), C-compatible | ✔ (extension) |
| Importing C headers: `using Name from "header.h";` (libclang, a `.ffi` cache), `nint`/`nuint`, structs by value | ✔ (see [FFI.md](FFI.md)) |
| `unsafe`: pointers, `&`, `*`, pointer arithmetic, `Memory.Allocate/Free` | ✔ |
| Entry point: `int Main()`, `void Main()`, `Error<int> Main()` | ✔ |
| `Error<void>` (a result with no value; `return;` or falling off the end of the function = success) | ✔ (extension) |
| Top-level `const`, `default(T)`, `foreach` over structs with `Count()`/`Get(int)` | ✔ (extension) |
| Standard library: `List<T>`, `Dictionary<K,V>`, `File`, `Directory`, `Encoding`, `Math`, string helpers | ✔ (see below) |
| Real OS threads: `thread` functions (only callable via `start`), `Thread`/`Thread<T>` (`Join`/`Cancel`/`is`), `SharedPtr<T>` | ✔ (extension, see [threading.md](docs/language/threading.md)) |

### Interpretation and extensions beyond the design

The design document leaves a number of things open; these are the decisions that were made:

* **Creating errors:** `return error("text");` or `error("text", code)`; `Error<T>` has `.Message` and `.Code`.
* **Implicit conversion** `T → Error<T>` / `T → Optional<T>`; `null` stands for "no value" (`Optional`).
* **Bool semantics** of `Error`/`Optional` apply in conditions and with `!`, `&&`, `||`, but not as an argument for a
  `bool` parameter (use `x is T` instead).
* **`is`/`case` patterns:** `x is int v` binds the value; `x is Error<int> r` binds the whole result. Pattern
  variables are scoped to the `if`/`while`, or to the `case`.
* **`try` in `int Main()`:** in the design's target picture, `try` is used in an `int` function. There, an error
  prints `error: <text>` to stderr and ends the program with exit code 1.
* **Integer arithmetic** works like in C#: types smaller than 32 bits are widened to `int`; a literal adapts to the
  other operand (`uint8 x = 200; int y = x * 3;` gives 600). Explicit casts never abort (they wrap/saturate); only
  `+ - * / %` are checked.
* **Interfaces** are, for now, only usable as a constraint and in base lists, not as a variable/parameter type (that
  would need fat pointers for dynamic dispatch without boxing).
* **Methods on `const ref` objects** operate on a copy (like C#'s `in`), so the read-only guarantee holds.
* **Built in** (generated directly by the compiler as IR, no runtime library): `Console.Write/WriteLine`,
  `Memory.Allocate/Free`, `Environment.Exit/Panic`, `Array.Copy`, `string.FromBytes`,
  `ToString()`/`CompareTo()`/`Equals()`/`GetHashCode()` on numbers, `int.MaxValue/MinValue`,
  `EmbedText("file")`/`EmbedNames("folder", ".ext")`/`EmbedTexts("folder", ".ext")` (files are embedded into the
  program at compile time; paths are relative to the source file, and only string literals are accepted as
  arguments). Everything else is in the standard library (next section) or comes via `extern "C"`.
* **`Error<void>`:** `Error<void> Save() { ... return; }`. `try Save();` only checks for an error; there is no
  `Optional<void>`.
* **Constants:** `const int MyConst = 5;` at the top level or inside functions. Numbers, `bool`, `char`, enums and
  `string` are allowed; a constant must always be initialized, and the initializer consists only of literals,
  operators, casts, enum values and other constants (`const Color Fav = Color.Green;`,
  `const Flags Rw = Flags.Read | Flags.Write;`, `const int Sum = A * 2 + 1;`). Top-level constants may be used before
  their declaration and are always checked, even if nothing uses them; they can also be accessed qualified
  (`Math.PI`). Local constants have no storage (assigning to one is an error) and may shadow a name from an
  enclosing block. **The compiler computes constants at compile time**
  (`compiler/src/ConstEval.cpp`, in `cshc`: `ConstEval.csh`), following the same rules as the code that would be
  generated for the expression at run time (the type of literals, promotion of small integers, shifts, comparisons,
  casts that saturate floating-point values, string concatenation with numbers, `sizeof(T)`), but it reports
  overflow (`2147483647 + 1`), division by zero, and `MIN / -1` as compile errors. The same expressions are allowed
  for the values of enum members (`B = A * 2`, `C = sizeof(int64)`); `&&`/`||` only evaluate the right side when it
  can change the result.
* **Global variables:** `int Counter;`, `string Name = "x";`, `List<string> Names = List<string>.Create();` at the
  top level, of any type. Without an initializer, the variable starts at its zero value. Initializers are arbitrary
  expressions; they run before `Main`, in the order of the declarations (files in the order they're given to the
  compiler). **The order is checked:** an initializer must not use a global that's initialized later (or itself) —
  not even through functions it calls (function pointers it creates count too). A global with no initializer (zero
  value) can be read at any time. Name resolution works like for constants (the file's namespace, `using`,
  qualified as `Ns.Counter`). Globals are ordinary lvalues (assign to them, `ref`, `&` in `unsafe`, modify
  fields/elements, call methods; a function-pointer global calls like a function). Values that own heap blocks
  (strings, arrays, lists, …) are released once `Main` returns. No `var` (the type must be written out). A
  `thread` function may never read or write a global, even through a function it calls (checked at compile time).
* **`foreach` over structs:** works for any struct with `int Count()` and `T Get(int index)` (e.g. `List<T>`).
* **Name resolution** works like in C#: the current file's namespaces and the global namespace win over `using`
  namespaces.
* **Function pointers:** `Action`, `Action<T1, …>` (no result) and `Func<R>`, `Func<T1, …, R>` (the last type is the
  result) are built-in types like in C#, with up to 8 parameters. They are plain pointers to functions,
  **with no closures/lambdas**: you can assign the name of a free function or a `static` method
  (`Func<int, int> f = Square;`, `var g = Add;`, `Handlers.Triple`). The signature must match exactly; for overloads
  and generic functions (`Identity<int>`, or inferred from the target type), the target type picks the match. Call
  with `f(x)`, `obj.Callback(x)` (a field), `table[i](x)`, or `f.Invoke(x)`. `null` is allowed; calling `null` is a
  panic. Compare with `==`/`!=`. Function pointers are ordinary values (fields, arrays, parameters, return values,
  type arguments). There are no `ref` parameters, and instance methods can't be assigned. They're C-compatible:
  passed to C (see [FFI.md](FFI.md)), C calls the CShift function directly; a function pointer returned from C can be
  called directly. `(void*)` casts need `unsafe`.
* Extra syntax allowed: `cond ? a : b`, `new int[3][]` (jagged arrays), `new T[] { ... }`, `sizeof(T)`.

## Standard library

The standard library is written in CShift itself (`stdlib/*.csh`) and embedded in the compiler. Only what a program
actually uses gets compiled (generics are instantiated per type). Examples are in `tests/cases/stdlib_*.csh`.

| Namespace | File | Contents |
|---|---|---|
| global | `core.csh` | `IDisposable`, `IComparable<T>`, `IEquatable<T>`, `IHashable`, `sqrt` |
| `System` | `list.csh`, `dictionary.csh`, `hashset.csh`, `stringbuilder.csh`, `process.csh`, `file.csh`, `directory.csh`, `encoding.csh` | `List<T>`, `Dictionary<K,V>`, `HashSet<T>`, `StringBuilder`, `Process`, `KeyValuePair<K,V>`, `File`, `Directory`, `Path`, `Encoding` (`using System;`) |
| `Char` | `char.csh` | `Char.IsDigit/IsLetter/IsLetterOrDigit/IsHexDigit/IsWhiteSpace/IsUpper/IsLower/ToUpper/ToLower/HexValue` |
| `System.Native` | `args.csh` | a helper function for `Main(string[] args)` |
| `Math` | `math.csh` | math functions and constants (without `using`: `Math.Sqrt(2)`) |
| `String` | `string.csh` | string helpers, visible as methods on `string` |
| `System.Native` | `native.csh` | C imports (`fopen`, `sin`, `pthread_mutex/cond_*`, …), also usable by your own programs (`using System.Native;`) |
| `System` | `thread.csh` | `Thread`/`Thread<T>`, `SharedPtr<T>` (`using System;`, see [threading.md](docs/language/threading.md)) |

**`List<T>`** — a growable array. Create it with `List<int>.Create()` (or `new List<int>()`).
`Add`, `AddRange(T[])`, `Insert(i, v)`, `RemoveAt(i)`, `Remove(v)`, `Clear()`, `Get(i)`, `Set(i, v)`, `Count()`,
`Capacity()`, `IndexOf(v)`, `Contains(v)` (T: `IEquatable<T>`), `Sort()` (T: `IComparable<T>`, stable), `Reverse()`,
`ToArray()`; `foreach (var x in list)` works. An invalid index ends the program with a panic.

**`Dictionary<TKey, TValue>`** — a hash table. `Create()`, `Set(k, v)`, `Add(k, v)` (`Error<void>`, fails on a
duplicate key), `TryGet(k)` (`Optional<TValue>`), `GetOrDefault(k, fallback)`, `ContainsKey(k)`, `Remove(k)`,
`Clear()`, `Count()`, `Keys()`, `Values()`, `Entries()` (`KeyValuePair<K,V>[]`). Keys must satisfy `IEquatable` and
`IHashable`: numbers, `bool`, `char`, enums and `string` do so out of the box; your own structs define
`bool Equals(T other)` and `int GetHashCode()`.

> Since there are no classes, `List` and `Dictionary` are small structs that point at shared storage: copies
> (assignment, arguments) see the same elements. The storage is created by `Create()`, or by the first `Add`/`Set`; an
> empty list from `new List<T>()` isn't yet connected to its copies before the first element is added — start with
> `Create()` if you hand it out before adding to it.

**`StringBuilder`** — builds text without copying on every `+`: `var sb = StringBuilder.Create(); sb.Append("x"); sb.Append('c'); sb.AppendLine("…");
sb.Length(); sb.Get(i); sb.Clear(); string s = sb.ToString();` (a handle to shared storage, like `List`).
**`HashSet<T>`** — `Create()`, `Add(v)` (`true` if it was new), `Contains(v)`, `Remove(v)`, `Count()`, `Clear()`,
`ToArray()`.
**`Process.Run("command")`** runs a command line through the shell and returns its exit code; `RunCapture("command")`
also captures what it wrote to stdout (`Optional<string>`); `GetEnv("NAME")` reads an environment variable
(`Optional<string>`); `IsWindows()` reports the platform.
**`Directory`** — `Exists(path)`, `Create(path)` (including parent directories), `GetEntries(path)` (names, sorted),
`FindFiles(path, extension)` (recursive, sorted). **`Path`** — `Combine`, `Normalize`, `GetDirectory`, `GetFileName`,
`GetExtension`, `GetStem`, `ChangeExtension`.
**Command line:** `int Main(string[] args)` receives the arguments without the program name. `Console.WriteError(Line)`
writes to stderr, `string.FromCStr(char*)` copies a C string (`unsafe`) into a `string`.

**`File`** (static, text is UTF-8 by default): `ReadAllText(path [, encoding])`, `ReadAllBytes(path)`,
`WriteAllText(path, text [, encoding])`, `WriteAllBytes(path, bytes)`, `Exists(path)`, `Delete(path)`. Reading returns
`Error<string>` or `Error<uint8[]>`, writing and deleting return `Error<void>`; a UTF-8 BOM is skipped when reading
text. Paths go to the C library unchanged (so, on Windows, no non-ASCII characters in the path).

```csharp
using System;

Error<string> Load(string path)
{
    var text = try File.ReadAllText(path);
    try File.WriteAllText(path + ".bak", text);
    return text.Trim();
}
```

**`Encoding`** — `Encoding.UTF8()` and `Encoding.ASCII()`: `GetBytes(string)`, `GetString(uint8[] [, start, count])`
(`Error<string>`: invalid UTF-8, or bytes above 127 for ASCII, are errors), `GetByteCount`, `Name()`. Strings are
always UTF-8 in memory; `GetBytes` with ASCII replaces other characters with `?`. More encodings can be added as a
new `EncodingKind`.

**`Math`** — constants `PI`, `E`, `Tau`; `Abs`/`Min`/`Max`/`Clamp` (int, int64, float, double), `Sign`; `Sqrt`,
`Cbrt`, `Pow`, `Exp`, `Log`, `Log2`, `Log10`, `Hypot`; `Sin`, `Cos`, `Tan`, `Asin`, `Acos`, `Atan`, `Atan2`, `Sinh`,
`Cosh`, `Tanh`, `DegreesToRadians`, `RadiansToDegrees`; `Floor`, `Ceiling`, `Truncate`, `Round` (rounds half to even,
like in C#), `Lerp`, `IsNaN`, `IsInfinity`. Integer arguments are widened to `double` (`Math.Sqrt(2)`).

**String helpers** (`s.Contains(x)` ≙ `String.Contains(s, x)`, static as `string.Join(sep, parts)`): `IsNullOrEmpty`,
`Contains`, `IndexOf`, `LastIndexOf`, `StartsWith`, `EndsWith`, `Trim`, `ToUpper`/`ToLower` (ASCII only), `Replace`,
`Repeat`, `Split` (by character or string), `Join`, `ParseInt`/`ParseInt64`/`ParseDouble` (`Error<…>`), plus
`Equals`, `GetHashCode` (FNV-1a) and `CompareTo` (byte-wise). Positions are byte offsets;
`string.FromBytes(bytes [, start, count])` builds a string from bytes. New helpers are just written as a function in
`namespace String` (the first parameter is the string).

**`Thread`/`Thread<T>`** — the handle returned by `start`ing a `thread` function (`start Foo(args)`; calling one
directly, without `start`, is a compile-time error): `Join()`, `Cancel()`, `CancelAndWait()`, `IsCompleted()`,
`IsCancelled()`, and (`Thread<T>` only) the non-blocking `t is T value` pattern. Real OS threads (pthreads on
every supported platform), isolated from global state and restricted to plain-value (or `SharedPtr<T>`)
parameters — see [threading.md](docs/language/threading.md) for the full story, including `Thread.Cancelled`.
**`SharedPtr<T>`** — `Create(value)`, `Get()`, `Ptr()` (`unsafe`), `IsNull()`: a box with an atomically
reference-counted handle, safe to share between threads (unlike strings/arrays/containers).

## Compiler structure

| File | Contents |
|---|---|
| `compiler/src/Lexer.*` | the tokenizer (UTF-8, escapes, number literals) |
| `compiler/src/Parser.*`, `AST.h` | recursive descent with backtracking for generics, casts, declarations |
| `compiler/src/Types.*` | interned types (pointer equality = type equality) |
| `compiler/src/CodeGen.*` | symbol tables, type resolution, struct layout, generics instantiation, constraints |
| `compiler/src/CodeGenExpr.cpp` | expressions, conversions, arithmetic with overflow checks, `is`/`try` |
| `compiler/src/CodeGenCall.cpp` | overload resolution, type inference, calls, built-in functions |
| `compiler/src/CodeGenStmt.cpp` | statements, scopes, cleanup (ARC, `using`), function bodies |
| `compiler/src/CodeGenRuntime.cpp` | ARC helpers, strings, panics — generated directly as LLVM IR |
| `compiler/src/ConstEval.cpp` | the compile-time evaluator: constants, enum values, `sizeof(T)` |
| `stdlib/*.csh` | the standard library, written in CShift; CMake embeds it in the compiler as byte arrays (`StdlibData.cpp`) |
| `compiler/src/main.cpp` | the driver: command line, optimization, object file, linking |
| `compiler/src/Project.*` | reading the project file `cshift.json`, `cshiftc new` |
| `compiler/src/Ffi.h`, `FfiImport.cpp` | `using X from "…"`: the `.ffi` cache (freshness by hash), building declarations from the `.ffi` file |
| `compiler/src/FfiGenerator.cpp` | compiling a C header (via libclang, loaded at runtime) into a `.ffi` file and a C wrapper for struct values |
| `compiler/src/Dump.*`, `DumpAst.cpp` | a development aid: `--dump-tokens` / `--dump-ast` (for comparing against `selfhost/`) |
| `selfhost/` | the compiler written in CShift: a lexer and parser (verified against the C++ compiler) and a code generator that covers almost the whole language (writes LLVM IR as text, clang compiles it); see [selfhost/README.md](selfhost/README.md) |
| `.github/workflows/release.yml`, `packaging/` | the release workflow (Windows/Linux) and the scripts that assemble the archive folder with its toolchain |

There is no separate type-checking phase: type checking and code generation happen in one pass over the AST. That
makes monomorphization straightforward (a generic function's body is walked again for every type combination).

**Reference counting:** variables, fields and array elements own a reference; intermediate results carry a "+1" that
is either taken over when stored, or released at the end of the statement. Arguments are passed borrowed; the called
function retains its own parameters itself. Heap blocks (strings/arrays) have the header
`{int64 refcount, int64 length}`. `--arc-stats` lets you check that every allocation was eventually released.

## Tests

```
tests/run_tests.sh [path/to/cshiftc] [-O0..-O3]      # or .\build.ps1 -Test
```

* `tests/test.csh` (+ `tests/mathlib.csh`): a large test program with ~165 checks covering every area of the
  language. Its output is compared against `tests/test.expected`, and the ARC balance must come out even too.
* `tests/cases/*.csh`: small programs with expectations written as comments — compiler errors (`err_*`), runtime
  panics (`panic_*`), program behavior (`main_*`), an ARC stress test, special cases (`misc_features`, `builtins`,
  `error_void`, `const_default`) and the standard library tests (`stdlib_*`; `stdlib_file` creates files in the
  temp directory).
* `tests/projects/ffi`: a C library (`native/geo.c`, compiled with clang by the test runner) via
  `using Geo from "geo.h"`: pointers, strings, structs by value, opaque handles, callbacks in both directions; plus
  `native_int`, `function_pointers` (+ `err_function_*`, `panic_null_function`) and import errors.

## Known limitations / next steps

* The standard library is small: no streams, no `Stack`/`Queue`, no further encodings, no date/time functions, no
  formatting (`Format`, interpolation). There's no indexer (`list[i]`); it's `Get`/`Set` instead.
* Interfaces as a value type (dynamic dispatch), lambdas/closures, and passing structs *by value* in a hand-written
  `extern "C"` (it works via `using X from "header.h"`) are still missing. Limits of header imports: [FFI.md](FFI.md).
* Reference counts of strings, arrays and the built-in containers are not atomic. Threads (`thread`,
  `Thread`/`Thread<T>`, see [threading.md](docs/language/threading.md)) are isolated from global state and their
  parameters are restricted to plain values and `SharedPtr<T>` (which *is* atomically reference-counted) exactly
  because of this; sharing a string/array/container between threads yourself is still unsafe.
* Generic bodies are only checked upon instantiation (like C++ templates); unused generic functions are not analyzed.
* No debug information (DWARF/PDB).
* Error messages: after a syntax error, semantic analysis no longer runs.
