# CShift

CShift is a native, C#-like systems language: structs instead of classes, no GC (ARC), no headers, generics via
monomorphization, errors as values, lambdas, interface values, real OS threads, and direct C interop (C headers are
imported as they are).

The compiler, `cshiftc`, is **written in CShift itself** ([selfhost/](selfhost/README.md)). It writes LLVM IR as text;
clang optimizes it, generates machine code and links:

```
source (.csh) ─▶ lexer ─▶ parser ─▶ syntax tree ─▶ type checking + code generation ─▶ LLVM IR (text) ─▶ clang ─▶ .exe
```

The first compiler, written in C++17 against the LLVM API ([compiler/](compiler/README.md)), is **frozen**: it is only
the stage 0 that builds the self-hosted compiler from source. New language features exist only in the self-hosted
compiler.

```csharp
using System;

interface IShape { double Area(); }

struct Circle : IShape
{
    double R;
    double Area() { return Math.PI * R * R; }
}

Error<int> Parse(string text)
{
    if (text.ParseInt() is int value)
        return value;
    return error($"'{text}' is not a number");
}

int Main()
{
    var shapes = List<IShape>.Create();
    shapes.Add(Circle { R = 1.0 });
    shapes.ForEach(s => Console.WriteLine($"area {s.Area()}"));

    int n = try Parse("42");        // an error ends Main with the message
    Console.WriteLine(n);
    return 0;
}
```

**Documentation:** [docs/](docs/README.md) — the [language guide](docs/language/README.md), the
[standard library](docs/stdlib.md), [C interop](docs/ffi.md), [projects](docs/build.md) and
[the compiler](docs/compiler.md).

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

**Standalone executable:** each release also has a single, self-contained file - `cshift-1.05-windows-x64-standalone.exe`
/ `cshift-1.05-linux-x64-standalone` - with the same toolchain embedded in it. Nothing to extract or add to `PATH`:
run it, and the first time it actually needs the toolchain (linking, or `using X from "header.h";`) it unpacks
itself once into a per-user cache directory. See [packaging/make-standalone.sh](packaging/make-standalone.sh).

**Publishing a release:** push a `release/vX.XX` branch (e.g. `release/v1.05` → version `1.05`, tag `v1.05`). The
workflow [.github/workflows/release.yml](.github/workflows/release.yml) builds the compiler for both platforms, runs
the tests (including once more against the fully assembled archive), and publishes the release. Pushing to the same
branch again replaces the release. The branch has to contain the workflow file, so branch off from a commit at or
after this one. The archives themselves are built by [packaging/](packaging/).

## Building it

The compiler is built in three stages ([selfhost/build-release.sh](selfhost/build-release.sh)):

| Stage | What | Built by |
|---|---|---|
| 0 | the frozen C++ compiler (`build/cshiftc`) | CMake, a C++17 compiler and the LLVM development packages |
| 1 | the self-hosted compiler (`cshc`) | stage 0 |
| 2 | the self-hosted compiler again: **the released `cshiftc`** (`build/stage2/cshiftc`) | stage 1 |

Stage 1 and stage 2 must generate identical LLVM IR for the compiler's own sources (the bootstrap check). If you
already have a `cshiftc` release, it can take the place of stage 0: `cshiftc build selfhost` is all it takes.

### Windows (recommended: MSYS2)

Visual Studio doesn't come with the LLVM libraries needed for stage 0; MSYS2 does:

```powershell
winget install MSYS2.MSYS2
# Once, in the "MSYS2 CLANG64" shell:
pacman -S --needed mingw-w64-clang-x86_64-clang mingw-w64-clang-x86_64-llvm `
                   mingw-w64-clang-x86_64-cmake mingw-w64-clang-x86_64-ninja

.\build.ps1          # stage 0 into .\build\cshiftc.exe
.\build.ps1 -Test    # also stages 1 and 2 (build\stage2\cshiftc.exe) and the tests
```

The compiler needs `clang` to compile and link; it looks for it in a `toolchain` folder next to itself, then in
`PATH`, then in `C:\msys64\clang64\bin` (or `%MSYS2_ROOT%\clang64\bin`); `--cc <path>` or `CSHIFT_CC` override it.

### Linux / macOS

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release   # stage 0; add -DLLVM_DIR=<llvm>/lib/cmake/llvm if needed
cmake --build build
bash selfhost/build-release.sh build/cshiftc dev build/stage2   # stages 1 and 2
bash tests/run_tests.sh build/stage2/cshiftc
```

## Usage

```
cshiftc [options] file.csh [more.csh ...]      compile files into one program
cshiftc new hello                              a new project: hello/cshift.json, hello/src/main.csh
cshiftc run hello                              build and run (without an argument: the cshift.json here or above)
cshiftc build                                  build only  ->  bin/<name>[.exe]
```

`cshiftc --help` lists the options (`-o`, `-O0..-O3`, `--target`, `--cc`, `-l`/`-L`/`-I`/`-D`, `--emit-llvm`,
`--arc-stats`, ...). All files of a program form one unit: types and functions can be used before their definition,
in any file. Errors are printed as `file:line:column: error: text`.

A project is described by a `cshift.json` (sources, output, libraries, per-platform settings; see
[docs/build.md](docs/build.md)). C libraries are used without hand-written declarations: `using Zlib from "zlib.h";`
imports the header as a namespace ([docs/ffi.md](docs/ffi.md)). Two complete examples with C libraries and VS Code
tasks: [demo-minifb/](demo-minifb/) (a MiniFB window) and [demo-opengl/](demo-opengl/) (OpenGL 3.3 with GLFW).

## VS Code

The `vscode-extension/` folder has an extension for `.csh` files (syntax highlighting, snippets, brackets/comments) —
see [vscode-extension/README.md](vscode-extension/README.md).

## Tests

```
tests/run_tests.sh [path/to/cshiftc]      # or .\build.ps1 -Test
```

`tests/test.csh`, the cases in `tests/cases/` (compiler errors, panics, features, standard library), the projects in
`tests/projects/`, and the self-hosting checks (the compiler rebuilds itself to the same IR). Details:
[docs/compiler.md](docs/compiler.md#tests).

## Known limitations

* The compiler stops at the first error, and generic bodies are only checked when they are instantiated (there is no
  separate semantic pass yet).
* Reference counts of strings, arrays and containers are not atomic: threads get copies of strings, and share values
  only through `SharedPtr<T>` and `Mutex<T>` (whose values must be copyable between threads, so no containers yet).
* Lambdas capture read-only copies; generic type arguments are not inferred from lambdas.
* No debug information (DWARF/PDB), no streams, dates or number formatting options in the standard library.
* More in [Todo.md](Todo.md).
