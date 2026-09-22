# Importing C headers (FFI)

With `using Name from "header.h";`, CShift imports the declarations of a C header as a namespace. Functions, structs,
enums and constants no longer have to be hand-written as `extern "C"`.

```csharp
using Zlib from "zlib.h";

int Main()
{
    Console.WriteLine(Zlib.zlibVersion());          // const char* -> string
    Console.WriteLine(Zlib.Z_BEST_COMPRESSION);     // macro -> constant
    Zlib.z_stream stream = default(Zlib.z_stream);  // C struct with the exact layout
    return 0;
}
```

```
cshiftc build          # cshift.json: "links": ["z"]
cshiftc prog.csh -lz   # single file
```

## How it works

1. The compiler parses the header with **libclang** and writes a **`.ffi` file** (JSON, easy to read) to
   `obj/ffi/<Name>.ffi` (relative to the project folder or the source file). It lists functions, structs, enums and
   constants with their CShift types.
2. The namespace's declarations are built from the `.ffi` file. The header is **only reparsed when something
   changed** (the content — an xxh3 hash — of the header and of every header that belongs to the API, the target,
   `-I`/`-D`, the format version). Otherwise the file is simply read, which costs milliseconds.
3. The library (`.a`, `.o`, `.lib`, `.so`) still has to be linked — via `links` in `cshift.json` or on the command
   line.

`using Name from "file.ffi";` uses an existing `.ffi` file directly. That doesn't need libclang (e.g. when bindings
are shipped with the project); only the wrapper file for struct values (see below) pulls in the header. The header is
looked up relative to the source file, then in the `includePaths` (`-I`), and finally in `clang`'s system include
directories.

### Requirements

* `clang` (linker/shims) and **libclang** (`libclang.dll` / `libclang.so` next to or under clang's directory).
  `cshiftc` only loads libclang once a header actually needs to be parsed; the `CSHIFT_LIBCLANG` environment variable
  overrides the path.
* Errors in the header (includes not found, unknown types) abort the import with clang's message — otherwise types
  would silently become `int`. Missing macros or paths are given via `includePaths` and `defines`.

## Project file

```json
{
	"name": "app",
	"includePaths": ["third_party/sqlite"],
	"defines": ["SQLITE_OMIT_LOAD_EXTENSION"],
	"libraryPaths": ["third_party/lib"],
	"links": ["sqlite3", "third_party/lib/libminifb.a"]
}
```

| Key | Meaning | Command line |
|---|---|---|
| `includePaths` | search paths for C headers (relative to `cshift.json`) | `-I<dir>` |
| `defines` | macros used when parsing the headers | `-D<name>[=value]` |
| `libraryPaths` | linker search paths | `-L<dir>` |
| `ffiApi` | path fragments of headers that belong to the imported API even from system include paths (umbrella headers) | `--ffi-api=<text>` |
| `links` | an entry with no path/extension: a library name (`-l<name>`); an entry with a path or the extension `.a .o .obj .lib .so .dylib .dll`: a file that's linked directly | `-l<name>`, `file.a` |

## Mapping of C types

| C | CShift |
|---|---|
| `char` / `signed char` / `unsigned char` | `char` / `int8` / `uint8` |
| `short`, `unsigned short` | `int16`, `uint16` |
| `int`, `unsigned int` | `int32`, `uint32` (stays `int`!) |
| `long`, `unsigned long` | `int32`/`int64` depending on the target (Windows: 32-bit, Linux/macOS: 64-bit) |
| `long long` | `int64`, `uint64` |
| `size_t`, `uintptr_t` / `ssize_t`, `ptrdiff_t`, `intptr_t` | **`nuint`** / **`nint`** |
| `float`, `double` | `float32`, `double` |
| `_Bool`, `bool` | `bool` |
| `enum E` | `enum E` (base type taken from C) |
| `struct S` | `struct S` with exactly the C layout |
| `struct S` without a definition (an opaque handle) | usable only as a pointer, `S*` |
| `void*` | `void*` |
| function pointer `R (*)(A, B)` | `Func<A, B, R>` / `Action<A, B>` (see below) |
| `const char*` | `string` |
| `union`, bit fields, arrays inside structs | filler bytes in the layout (the size is right, but there's no field access) |
| `long double` | the function is skipped |

The name of a struct/enum type is its **typedef name**, if it has one (`z_stream`, not `z_stream_s`).

**`nint` / `nuint`** are integers the size of a pointer (like `IntPtr`/`UIntPtr` in C#): 64 bits on 64-bit targets.
`int` values and anything smaller convert to `nint`/`nuint` implicitly; `nint`/`nuint` convert to `int64`/`uint64`
implicitly, but the other direction needs a cast (on 32-bit targets that would lose information). `int` and `uint`
keep their fixed 32-bit size — which is why C's `int` is deliberately mapped to `int32` and not to `nint`.

### Pointers

| C parameter | CShift | Call |
|---|---|---|
| `T* p` (a pointer to a value) | `ref T` | `f(ref x)`; `null` or a `T*` are also accepted (the pointer may be `NULL`) |
| `const T* p` | `const ref T` | `f(x)`; `null` or `T*` are also accepted |
| `const char* s` | `string` | `f("text")`; `null` becomes `NULL` |
| `char* buffer` | `char*` | an unsafe pointer (`unsafe`) |
| `void*` | `void*` | |
| function pointer | `Action<...>` / `Func<..., R>` | a function, or `null` |
| `Handle*` (an opaque type) | `Handle*` | an unsafe pointer, only passed along |
| `T**` | `ref T*` | an output parameter: `f(ref handle)` |

Return values stay raw pointers; only `const char*` is **copied** into a `string` (`NULL` → `null`). The pointer
still belongs to the library; the string is an independent copy.

The `ref`/`constref`/`nullable` field in the `.ffi` file controls this behavior per parameter. A pointer to an array
(`int* values`, `size_t count`) is mapped to `ref int`; a pointer to several elements is passed as a raw `int*`
(`unsafe`).

### Structs *by value*

C functions that take or return a struct by value (`GeoPoint geo_add(GeoPoint a, GeoPoint b)`) are ABI-dependent
(registers or memory, depending on the platform and size). For these, the compiler generates a small **C wrapper
file** (`obj/ffi/<Name>.shim.c`) alongside the `.ffi` file, which is compiled with `clang` and linked automatically.
That way clang handles the platform-specific argument passing; in CShift you just see ordinary functions with struct
values:

```csharp
Geo.GeoPoint p = Geo.geo_point_add(Geo.geo_point_make(1, 2), Geo.geo_point_make(10, 20));
```

The wrappers reference every such function in the library, so the library has to be linked as soon as the header
contains such functions — even if you never call them.

### Callbacks (function pointers)

C function pointers become the built-in types `Action<...>` (no result) and `Func<..., R>` (with a result, the last
type argument being the result) — up to 8 parameters, no closures. You pass the name of a CShift function, or `null`:

```csharp
using Mfb from "MiniFB.h";

// typedef void (*mfb_keyboard_func)(struct mfb_window*, mfb_key, mfb_key_mod, bool)
//   ->  Action<mfb_window*, mfb_key, mfb_key_mod, bool>
void OnKey(Mfb.mfb_window* window, Mfb.mfb_key key, Mfb.mfb_key_mod mod, bool pressed)
{
    if (pressed && key == Mfb.mfb_key.KB_KEY_ESCAPE)
        Mfb.mfb_close(window);
}

Mfb.mfb_set_keyboard_callback(window, OnKey);
```

A callback receives the C values unchanged: pointers are raw pointers (`const char*` → `char*`, `const S*` → `S*`;
accessing them needs `unsafe`), and there's no `string`/`ref` conversion. A pointer to `void*` user data (`void*
user`) is cast back (`(int*)user`). A C function that *returns* a function pointer gives you a `Func<...>` that you
call directly. Function pointers inside structs (`GeoOps.fn`) are `Action`/`Func` as well. More detail is in the
README (the function pointers section).

### Constants and enums

Integer, floating-point and string macros (`#define VERSION 3`, `(FLAG_A << 1)`) become constants of the namespace;
enum values are constants of the enum type, reachable through the enum's name too: `Geo.GEO_GREEN`,
`Geo.GeoColor.GEO_GREEN`. Function-like macros are not supported.

## Limits

Not carried over (listed in the `skipped` field of the `.ffi` file with a reason; using one reports "undefined
name"):

* global variables of the header, `long double`, `__int128`
* accessing union fields, bit fields and arrays inside structs (the layout is still correct)
* packed structs (`#pragma pack`): the import aborts with a layout error
* callbacks with struct values as a parameter or result, variadic function pointers, more than 8 parameters: these
  stay `void*`
* variadic functions with struct values (variadic functions with plain values, like `printf`, work)
* C only, no C++ (namespaces, classes, templates)

## Umbrella headers and libraries in system paths

A header from a system include path (`llvm-c/Core.h`, `zlib.h`) only brings in its own declarations; headers it
includes are treated as system headers and are not imported. To pull several headers of a library into **one**
namespace, write your own header that includes them (an *umbrella header*), and list in the project file which path
fragments belong to the API:

```json
{
	"includePaths": ["C:/msys64/clang64/include"],
	"ffiApi": ["llvm-c/", "llvm/Config"]
}
```

```c
/* native/llvm.h */
#include <llvm-c/Core.h>
#include <llvm-c/TargetMachine.h>
```

```csharp
using Llvm from "native/llvm.h";
```

On the command line: `--ffi-api=<text>`. A `const char*` parameter (`string` in CShift) also accepts a raw `char*`,
such as a pointer returned by another C function (`string.FromCStr(char*)` copies a C string into a `string`).
