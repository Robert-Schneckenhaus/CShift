# The cshiftc command

`cshiftc` builds, runs, checks and publishes CShift programs. It works on a project (a folder with a `cshift.json`,
see [projects and the build](build.md)) or on single source files. `cshiftc --help` prints a short version of this
page.

```
cshiftc new hello            a new project
cshiftc run hello            build it and run it
cshiftc publish hello        the program for the browser: hello/bin/hello.html
```

## Commands

| Command | What it does |
|---|---|
| `cshiftc [options] a.cshift b.cshift` | compiles the files into one program, without a project |
| [`cshiftc new <folder>`](#new) | creates a project: `cshift.json`, `src/main.cshift`, `.gitignore` |
| [`cshiftc build [project]`](#build-and-run) | builds the project: `bin/<name>` (`.exe` on Windows) |
| [`cshiftc run [project] [-- args]`](#build-and-run) | builds the project and runs it; the arguments after `--` go to the program |
| [`cshiftc publish [project \| files]`](#publish) | the program for the browser: one HTML file with everything in it |
| [`cshiftc serve [project \| files]`](#serve) | `publish` on a local web server, built again when a file changes |
| [`cshiftc check [project \| files]`](#check-query-and-doc) | reports the errors and generates nothing |
| [`cshiftc query ...`](#check-query-and-doc) | answers questions about the code as JSON (for editors) |
| [`cshiftc doc [project \| files]`](#check-query-and-doc) | the doc comments as JSON |

`project` is a folder that has a `cshift.json`, or the path of the file itself. Without it, `cshift.json` is looked up
in the current folder and then in its parent folders, as `git` does. Options on the command line override the
project file.

Source files end in `.cshift`. `.csh`, the extension until 0.31, is still read.

## new

```
cshiftc new hello
cd hello
cshiftc run
```

The project builds an executable from the files in `src/`. The [app template](https://github.com/Robert-Schneckenhaus/cshift-app-template)
on GitHub is the same project with a CI workflow that builds it.

## build and run

```
cshiftc build                          the project in this folder (or above)
cshiftc build demo-ui -O0 -g           another project, without optimizations, with debug information
cshiftc run -- input.txt --verbose     run it: the program gets input.txt and --verbose
cshiftc hello.cshift -o hello          single files: hello.exe on Windows
cshiftc hello.cshift --run -- a b      single files, built and run with the arguments a and b
```

The output is `bin/<name>` (`output` in `cshift.json`, `-o` on the command line). `run` passes the exit code of the
program on.

The target decides what is built:

| Option | The program |
|---|---|
| (none) | a native program for this computer: Windows, Linux or macOS, with LLVM (clang optimizes and links) |
| `--backend wasm` | a WebAssembly module for WASI, with CShift's own backend; nothing else is needed ([WebAssembly](wasm.md)) |
| `--target wasm32-wasi` | a WebAssembly module with LLVM (needs clang, wasi-libc and wasm-ld) |
| `--target m68k-amigaos` | an AmigaOS program, with CShift's own 68000 backend ([the Amiga](amiga.md)) |

```
cshiftc build --backend wasm -o program.wasm
node tests/wasi-run.mjs program.wasm             # or: wasmtime --dir . program.wasm
cshiftc build demo-ui --target m68k-amigaos      # an Amiga program: copy it to the Amiga, or to an emulator's drive
```

## publish

```
cshiftc publish                  the project in this folder  ->  bin/<name>.html
cshiftc publish demo-snake       ->  demo-snake/bin/demo-snake.html
cshiftc publish hello.cshift     single files  ->  hello.html
cshiftc publish -o page.html     another name for the page
```

`publish` builds the program with the wasm backend and writes **one HTML file** that has everything in it: the
program, the runtime ([web/cshift.js](../web/cshift.js)) and the files that the program reads (`"assets"` in
`cshift.json`). The page loads nothing else: it opens with a double click and can be put on any web server as it is.

The page shows the program's console. A program with a window gets a `<canvas>` with the keyboard and the mouse:
[System.Ui](ui.md#in-the-browser), and GLFW with OpenGL (WebGL 2), game loop and all. The details, and what does not
work in the browser, are in [WebAssembly](wasm.md#a-program-for-the-browser-cshiftc-publish).

`--target` and `--backend` cannot be changed for `publish` (it always builds `--backend wasm`); `-O0` … `-O3` and
`-v` can be given.

## serve

```
cshiftc serve                                   http://localhost:8080/ (or the next free port)
cshiftc serve demo-ui --open                    and open it in the browser
cshiftc serve --port 3000 --host 0.0.0.0        reachable from other devices of the network
```

`serve` is `publish` that keeps going, like `vite` or `ng serve`. It builds the page and serves it. It watches the
files of the project and of its dependencies, and builds again when one changes. The page in the browser then
reloads itself. A failed build shows the compiler's errors on the page until the next build works. Ctrl+C ends the
server.

| Option | |
|---|---|
| `--port <n>` | the port; by default the first free one from 8080 on |
| `--host <address>` | where the server listens: `127.0.0.1` (this computer only, the default) or `0.0.0.0` (every network) |
| `--open` | opens the page in the browser |

## check, query and doc

These commands are used by editors and tools. They run the compiler's front end and generate no program.

```
cshiftc check                                   all errors of the project (up to 50), as file:line:column: error: text
cshiftc query --at src/main.cshift 12 8         the name at line 12, column 8: its type, documentation, definition
cshiftc query --at src/main.cshift 12 8 --references   the places where it is used
cshiftc query --at src/main.cshift 12 8 --rename       the places that renaming it changes (or why it cannot be)
cshiftc query --at src/main.cshift 12 9 --members      what can follow 'name.'
cshiftc query --outline src/main.cshift         the declarations of the file
cshiftc doc                                     the documentation of the standard library
cshiftc doc mylib --require-docs -o api.json    a library's documentation; every public declaration needs a doc comment
```

`query` writes JSON. With `--overlay <file> <text file>`, the text of `<file>` comes from `<text file>`, so an editor
can ask about text that is not saved yet. The [VS Code extension](../vscode-extension/README.md) uses `check` and
`query`. The format of `doc` is described in [doc comments](language/doc-comments.md).

## Options

| Option | |
|---|---|
| `-o <file>` | the output file |
| `-O0` … `-O3` | the optimization level (default `-O2`) |
| `-g` | debug information for gdb and lldb ([debugging](debugging.md)); best with `-O0` |
| `--target <triple>` | the target: `wasm32-wasi`, `m68k-amigaos`, or a triple of clang (default: this computer) |
| `--backend <name>` | the code generator: `llvm` (the default), `wasm` or `m68k` (the default for AmigaOS) |
| `--run` | single files: run the program after building it (its arguments after `--`) |
| `-c` | an object file only, not linked |
| `--emit-llvm` | write the LLVM IR (`.ll`) instead of a program |
| `--emit-asm` | m68k backend: write the assembly (`.s`) instead of a program |
| `--unchecked` | integer overflow wraps around instead of ending the program with a panic |
| `--checked` | integer overflow panics (the default; overrides `"unchecked": true` in `cshift.json`) |
| `-l<name>`, `-L<dir>` | a library to link, a search path of the linker; `file.a`, `file.o` are linked as they are |
| `-I<dir>`, `-D<name>[=value]` | an include path, a macro for C headers (`using X from "header.h"`, [C interop](ffi.md)) |
| `--ffi-api=<text>` | headers whose path contains `<text>` belong to the imported API |
| `--ndk <dir>` | the AmigaOS NDK, for libraries from SFD files |
| `--cc <program>` | the C compiler that links (default: `CSHIFT_CC`, the bundled toolchain, then `clang`) |
| `--stdlib <dir>` | use this standard library instead of the one built into `cshiftc` |
| `--arc-stats` | print the heap allocations and frees when the program ends (for debugging) |
| `-v` | verbose output |
| `--version` | print the version |
| `--clear-cache` | delete the toolchains that a standalone `cshiftc` has unpacked (all versions) |
| `-h`, `--help` | print the help |

## Environment variables

| Variable | |
|---|---|
| `CSHIFT_CC` | the C compiler that links (like `--cc`) |
| `CSHIFT_NDK` | the AmigaOS NDK (like `--ndk`) |
| `CSHIFT_WASI_SYSROOT` | the sysroot of WASI for `--target wasm32-wasi` ([WebAssembly](wasm.md#what-the-llvm-target-needs)) |
