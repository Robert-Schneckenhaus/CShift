# WebAssembly: the wasm32-wasi target

CShift programs can be compiled to WebAssembly. A `.wasm` file runs in any WebAssembly runtime with WASI (the system
interface: files, the clock, arguments, the console): node, wasmtime, wasmer, and in the browser with a WASI shim.

```
cshiftc --target wasm32-wasi hello.csh -o hello.wasm
wasmtime --dir . hello.wasm                     # or: node tests/wasi-run.mjs hello.wasm
```

```json
{
	"name": "demo",
	"sources": ["src"],
	"target": "wasm32-wasi"
}
```

## What is needed

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
| Files and directories | through WASI: the runtime decides what the program sees (wasmtime `--dir`, node's `preopens`). The program starts in the directory in the environment variable `PWD` if the host sets it (otherwise in `/`). |
| Time | `DateTime.Now` is UTC: WASI has no time zones. |
| Panics, exit codes | as on other targets (a panic exits with 101). |
| C headers | `using X from "header.h"` reads the headers of wasi-libc; native libraries of the host cannot be linked. |

## Running the tests

`CSHIFT_TARGET=wasm32-wasi bash tests/run_tests.sh` compiles the test programs for WebAssembly and runs them with node
([tests/wasi-run.mjs](../tests/wasi-run.mjs): the whole file system, the current directory in `PWD`). Cases that need
threads or other programs are skipped (`// skip-target: wasm32`), and so are the projects and the debugger tests,
which run programs directly. The CI does this on Linux after the native tests.
