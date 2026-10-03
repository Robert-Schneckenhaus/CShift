# Installing CShift and its dependencies

`cshiftc` itself is one small program. It generates LLVM IR and leaves the machine code and the linking to clang,
and it uses libclang to read C headers. The releases bring clang and libclang along (`toolchain/`). What they do not
bring on Linux is what every C program on the system already uses: the C library, the linker and gcc's startup
files. Those come from the distribution's packages, like for any other compiler there.

This page lists what is needed for what, and how to install it.

## Windows

Nothing. The archive (and the standalone `.exe`) contains clang, lld, libclang and the MinGW-w64 headers and
libraries. Unpack it, add the folder to `PATH`, and run `cshiftc new hello` and `cshiftc run hello`.

## Linux

### What is needed for what

| Needed for | Files | Debian / Ubuntu packages |
|---|---|---|
| running `cshiftc` | `libc.so.6`, `libm.so.6` (glibc 2.34 or newer) | (always installed) |
| running the bundled clang and libclang | `libstdc++.so.6` (GCC 12 or newer), `libgcc_s.so.1`, `libffi.so.8`, `libedit.so.2`, `libz3.so.4`, `libz.so.1`, `libzstd.so.1`, `libxml2.so.2` | `libstdc++6 libgcc-s1 libffi8 libedit2 libz3-4 zlib1g libzstd1 libxml2` |
| linking programs | the linker `ld`; `Scrt1.o`, `crti.o`, `crtn.o`, `libc.so` and `libm.so` of glibc; gcc's `crtbeginS.o`, `crtendS.o`, `libgcc.a`, `libgcc_s.so` | `build-essential` (or only `gcc libc6-dev`) |
| the standalone executable unpacking itself | `tar`, `gzip` | (always installed) |

On Debian and Ubuntu, everything at once:

```
sudo apt install build-essential libffi8 libedit2 libz3-4 zlib1g libzstd1 libxml2
```

The releases are built and tested on **Ubuntu 22.04**: Ubuntu 22.04 and newer and Debian 12 and newer work.

**Other distributions:** the bundled clang is built against the library versions of Ubuntu 22.04. Where the
distribution names a library differently (z3 is often `libz3.so.4.<minor>`, libxml2 2.14 and newer is
`libxml2.so.16`), the bundled clang does not start; `ldd` shows it (see below). Then use the distribution's clang
instead (see below) and install:

| Distribution | Packages |
|---|---|
| Fedora, RHEL | `sudo dnf install clang clang-devel gcc glibc-devel` |
| Arch | `sudo pacman -S clang gcc` |
| openSUSE | `sudo zypper install clang clang-devel gcc glibc-devel` |

(`clang-devel` and Arch's `clang` contain libclang, needed only for `using X from "header.h"`.) Distributions
with musl instead of glibc (Alpine) are not supported.

### Finding out what is missing

When a library for the bundled clang is missing, clang stops with `error while loading shared libraries:
libz3.so.4: cannot open shared object file` (or another file name) and `cshiftc` reports that linking failed. This
command lists all missing files at once:

```
ldd <cshift folder>/toolchain/bin/clang | grep "not found"
ldd <cshift folder>/toolchain/lib/libclang.so | grep "not found"
```

The package that contains a file can be found with `apt-file search libz3.so.4` (Debian/Ubuntu),
`dnf provides '*/libz3.so.4'` (Fedora) or `pkgfile libz3.so.4` (Arch).

When the linker or gcc's files are missing, linking fails with messages like `cannot find crt1.o`,
`cannot find -lgcc` or `"ld": No such file or directory`: install the package in the "linking programs" row.

### Using the distribution's clang

`cshiftc` looks for clang in this order: `--cc <path>`, the environment variable `CSHIFT_CC`, the `toolchain/`
folder next to itself, then `clang`, `cc` or `gcc` in `PATH`. So `--cc /usr/bin/clang` (or `CSHIFT_CC`, or deleting
`toolchain/`) makes it use the distribution's clang; clang 18 or newer works (tested with clang 18 and
22). The libraries in the second row of the table are then the distribution's business.

libclang (only for `using X from "header.h"`) is looked for in `CSHIFT_LIBCLANG`, next to clang
(`../lib/libclang*.so`) and as `libclang.so` in the system's library path; Debian and Ubuntu install it with
`libclang-dev`, Fedora with `clang-devel`, Arch with `clang`.

## Optional: only when you use it

| For | What | Debian / Ubuntu |
|---|---|---|
| `using X from "header.h"` with a C library | the library's development package (headers and `.so`) | e.g. `libglfw3-dev`, `libgl-dev` |
| `--target i686-linux-gnu` (32-bit programs) | the 32-bit C library and gcc files | `gcc-multilib` |
| `--target m68k-amigaos` (Amiga programs) | nothing: the m68k backend has its own assembler and linker | |
| `--backend wasm` (WebAssembly, [wasm.md](wasm.md)) | nothing to build; node or wasmtime to run the programs | `nodejs` |
| `--target wasm32-wasi` (WebAssembly through clang) | the C library of WASI, compiler-rt for wasm32, wasm-ld | `wasi-libc libclang-rt-<v>-dev-wasm32 lld-<v>` |
| AmigaOS libraries from SFD files | the NDK 3.2 (`--ndk`, see [amiga.md](amiga.md)) | download from Hyperion |
| running Amiga programs on the PC | vamos, FS-UAE or WinUAE | `pip install amitools`, `fs-uae` |
| the tests of the m68k backend under Linux | qemu and the m68k cross C library | `qemu-user gcc-m68k-linux-gnu` |
| the VS Code extension | VS Code; `cshiftc` in `PATH` or `cshift.compilerPath` | |
| debugging (`-g`, [debugging.md](debugging.md)) | gdb or lldb; in VS Code the CodeLLDB extension, which brings its own lldb | `gdb`, `lldb` |

## Building the compiler from source

See [compiler.md](compiler.md). It needs the same packages as above, and in addition:

* a CShift release as stage 0, downloaded by `selfhost/fetch-stage0.sh` with the GitHub CLI (`gh`),
* for the release packages: clang and libclang of LLVM 22 (`clang-22 libclang-22-dev` from apt.llvm.org) and
  `patchelf`,
* for the tests: `bash`; `node` for the tests of the VS Code extension.
