# WebAssembly: the wasm32-wasi target

CShift programs can be compiled to WebAssembly. A `.wasm` file runs in any WebAssembly runtime with WASI (the system
interface: files, the clock, arguments, the console): node, wasmtime, wasmer, and in the browser with a WASI shim.
There are two ways to get one:

```
cshiftc --backend wasm hello.csh -o hello.wasm          # CShift's own backend: nothing else needed
cshiftc --target wasm32-wasi hello.csh -o hello.wasm    # LLVM: clang, wasi-libc and wasm-ld
wasmtime --dir . hello.wasm                             # or: node tests/wasi-run.mjs hello.wasm
```

| | `--backend wasm` | `--target wasm32-wasi` (LLVM) |
|---|---|---|
| needs | nothing (the compiler writes the module itself) | clang, wasi-libc, compiler-rt for wasm32, wasm-ld |
| compiles | fast (the compiler builds itself in seconds), also inside the browser (the playground) | with LLVM's optimizations: faster code |
| C headers, C code (`using X from "h.h"`) | no | yes, compiled for WebAssembly |
| C library | its own, in CShift ([stdlib/wasm](../stdlib/wasm/libc.csh)), on WASI | wasi-libc |

```json
{
	"name": "demo",
	"sources": ["src"],
	"target": "wasm32-wasi"
}
```

## The wasm backend

`--backend wasm` (or `"backend": "wasm"` in `cshift.json`; the target is then `wasm32-wasi`) translates the LLVM IR of
the program itself into a WebAssembly module ([selfhost/src/Wasm](../selfhost/src/Wasm)): no clang, no linker, no C
library of the system. What the program needs of a C library (memory, files, directories, the clock, printf's
formatting, strtod, the math functions) is written in CShift and becomes a part of the program; only what is used is
in the module. The module imports WASI (`wasi_snapshot_preview1`), exports `_start` and `memory`, and gives the
program 8 MB of stack, like the LLVM target.

A function that is declared but not defined (`extern "C" void draw(int x);` without a body) is imported from the
module `env`: the host (JavaScript) provides it. The compiler warns about each one, so a missing function does not go
unnoticed. [tests/wasi-run.mjs](../tests/wasi-run.mjs) makes them fail when they are called.

The code is simple and correct first: values live in WebAssembly locals, structs in a frame on the shadow stack,
blocks become nested WebAssembly blocks. WebAssembly runtimes compile it further, so it is not slow, but LLVM's
optimizations make the code of `--target wasm32-wasi` faster.

The tests run with `CSHIFT_TARGET=wasm32-wasi CSHIFT_BACKEND=wasm bash tests/run_tests.sh`. They also run the cases
of the backend itself ([tests/wasm](../tests/wasm): suspending and resuming a program), and build the compiler as
WebAssembly with the backend: that compiler (under node) must build itself again, byte for byte.

## A program for the browser: `cshiftc publish`

```
cshiftc publish              # the project in this folder -> bin/<name>.html
cshiftc publish demo-snake   # -> demo-snake/bin/demo-snake.html
cshiftc publish hello.csh    # single files -> hello.html (-o names the page)
```

`publish` builds the program with the wasm backend and writes one HTML file that holds everything it needs: the
program (as Base64), the runtime [web/cshift.js](../web/cshift.js) and the files the program reads. The page loads
nothing, so it opens with a double click (as `file://`), and it can be put on any web server as it is. It shows the
program's console; a program with a window (GLFW) gets the `<canvas>` above it, with the keyboard and the mouse.
Programs and games run unchanged, game loop and all (see the next section).

The files that the program reads at run time (levels, pictures, texts) are listed in `cshift.json`:

```json
{
	"name": "game",
	"assets": ["data", "readme.txt"]
}
```

`assets` names files and folders (with everything below them) inside of the project. In the browser they are in the
program's file system at the same paths, relative to the current directory: `File.ReadAllText("data/level1.txt")`
reads the same file as in a native program that runs in the project folder. Files the program writes stay in memory
until the page is closed. (`embed("file")` is the other way: the file becomes a part of the program itself.)

### While working on it: `cshiftc serve`

```
cshiftc serve                # http://localhost:8080/ (or the next free port)
cshiftc serve demo-snake --open --port 3000
```

`serve` is `publish` that keeps going, like `ng serve` or `vite`: it builds the page, serves it on
`http://localhost:<port>/`, watches the files of the project (and of its `dependencies`) and builds again when one
changes; the page in the browser reloads itself. A build that fails shows the errors of the compiler on the page (and
in the terminal) until the next one works. `--open` opens the page in the browser, `--host 0.0.0.0` makes it reachable
from other devices of the network (by default only this computer can reach it), Ctrl+C ends the server. The output
folder (`bin/`), folders that start with `.` and `node_modules` are not watched. The server is written in CShift, on
`System.Net` ([Serve.csh](../selfhost/src/Driver/Serve.csh)).

## Games in the browser

A program with a window (GLFW) and OpenGL runs in the browser unchanged, game loop and all: `cshiftc publish` makes
a page of it (above). To build the page yourself, the `.wasm` goes next to the runtime and a page:

```
cshiftc build demo-snake --backend wasm -o program.wasm
cp web/cshift.js web/index.html .         # next to program.wasm
python3 -m http.server                    # open http://localhost:8000/
```

[web/cshift.js](../web/cshift.js) is the runtime of the page (one JavaScript module without dependencies):

| | In the browser |
|---|---|
| WASI | the console goes to the page (and to `console`), the clock, arguments, an in-memory file system with the files given to `run()` (`files: { "/data/map.json": "data/map.json" }`: fetched before the start; `publish` puts the `assets` there) |
| GLFW | the window is the `<canvas>`; keyboard, mouse, wheel and character callbacks; `glfwGetKey`, `glfwGetCursorPos`, `glfwGetTime`, the framebuffer size. Esc and `glfwSetWindowShouldClose` end the loop as on the desktop. |
| OpenGL | WebGL 2: the functions of OpenGL 3.3 core that WebGL 2 has, called directly (`extern "C" void glClear(uint32 mask);`) or through `glfwGetProcAddress`; GLSL `#version 330 core` becomes `#version 300 es`. From OpenGL 1.1: `glDrawPixels`, `glPixelZoom`, `glRasterPos2f` (a software renderer's picture, drawn as a texture). |
| the loop | `glfwPollEvents` (and `glfwWaitEvents`) suspends the program until the browser's next frame |

A browser shows a frame only when the program returns to it, but a game's loop never returns. The backend therefore
changes the functions that can reach `glfwPollEvents` (directly, or through a function pointer): when the runtime
suspends the program in that call, each of them saves its locals and returns; for the next frame the runtime calls the
program again, and each function restores its locals and continues in the call (like Binaryen's Asyncify). Programs
without such a call are not changed. The demos [demo-snake](../demo-snake) (a software renderer with `glDrawPixels`)
and [demo-opengl](../demo-opengl) (OpenGL 3.3 with shaders) run on the website's games page.

What does not work in the browser: the extensions of desktop OpenGL that WebGL 2 lacks (geometry shaders, `glMapBuffer`,
double precision), several windows, and sleeping (`Thread.Sleep` returns at once: the frame is the unit of time).

## What the LLVM target needs

clang compiles and links the program, so it needs the target's C library and linker:

| Part | Ubuntu / Debian | Elsewhere |
|---|---|---|
| the C library of WASI (wasi-libc) | `wasi-libc` (Ubuntu 24.04 and later) | [wasi-sdk](https://github.com/WebAssembly/wasi-sdk): `CSHIFT_WASI_SYSROOT=<wasi-sdk>/share/wasi-sysroot`, or only its `wasi-sysroot-<version>.tar.gz` |
| compiler-rt for wasm32 | `libclang-rt-<version>-dev-wasm32` | part of wasi-sdk |
| the linker `wasm-ld` | `lld-<version>` (or `lld`) | part of wasi-sdk |

`CSHIFT_WASI_SYSROOT` gives clang a sysroot of WASI when it does not find one by itself (`--sysroot`). The wasi-libc of
Ubuntu 22.04 (from 2020) is too old: its `rename` fails when it is called a second time. The CI uses the sysroot of
wasi-sdk 25.

## The language on WebAssembly

The language is the same. WebAssembly is a 32-bit target: `nint` and `nuint` have 4 bytes, and so have lengths and
indexes inside the runtime. The differences are those of the platform:

| | On WebAssembly |
|---|---|
| Threads | none: `start` is a compile error. `Mutex<T>` works (there is nothing to lock against). |
| Other programs | none: `Process.Run` returns -1, `Process.RunCapture` returns nothing. |
| Network | none: `TcpListener` and `TcpConnection` (`System.Net`) return `NetError.NotSupported`. |
| Files and directories | through WASI: the runtime decides what the program sees (wasmtime `--dir`, node's `preopens`). The program starts in the directory in the environment variable `PWD` if the host sets it (otherwise in `/`). |
| Time | `DateTime.Now` is UTC: WASI has no time zones. |
| Panics, exit codes | as on other targets (a panic exits with 101). |
| C headers | `using X from "header.h"` reads the headers of wasi-libc; native libraries of the host cannot be linked. |

## Running the tests

`CSHIFT_TARGET=wasm32-wasi bash tests/run_tests.sh` (add `CSHIFT_BACKEND=wasm` for the wasm backend) compiles the test programs for WebAssembly and runs them with node
([tests/wasi-run.mjs](../tests/wasi-run.mjs): the whole file system, the current directory in `PWD`). Cases that need
threads or other programs are skipped (`// skip-target: wasm32`), and so are the projects and the debugger tests,
which run programs directly. The CI does this on Linux after the native tests.
