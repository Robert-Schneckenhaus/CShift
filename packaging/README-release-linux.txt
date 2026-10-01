CShift @VERSION@ (Linux, x86-64)
================================

Installation
------------
1. Unpack this archive to a fixed location, e.g. into ~/cshift:

       tar -xf cshift-@VERSION@-linux-x64.tar.xz -C ~

2. Add the folder (containing cshiftc) to PATH, e.g. in ~/.bashrc:

       export PATH="$HOME/cshift-@VERSION@-linux-x64:$PATH"

3. Open a new shell and check:

       cshiftc --version
       cshiftc new hello
       cshiftc run hello

Requirements
------------
As with any C toolchain, the C library, the linker and gcc's startup files come from the system. On Ubuntu 22.04+
and Debian 12+:

    sudo apt install build-essential libffi8 libedit2 libz3-4 zlib1g libzstd1 libxml2

(build-essential: linking; the others: libraries the bundled clang needs, present on most systems.) Other
distributions, what each package is for and how to find a missing one: docs/install.md.

clang, libclang and the LLVM libraries live in the "toolchain" folder and are found by cshiftc itself. An existing
LLVM installation is neither needed nor used.

Contents
--------
cshiftc        the compiler
toolchain/     clang, libclang, LLVM libraries (do not modify)
README.md      language status, usage, the cshift.json project file
docs/install.md  the dependencies (Linux: which packages, other distributions)
docs/ffi.md    importing C headers (using Name from "header.h";), function pointers
tools/debug/   pretty printers for gdb and lldb (programs built with -g, see docs/debugging.md)
docs/          the language guide (docs/language), the standard library, the design documents

Your own C libraries: see docs/ffi.md and the includePaths/libraryPaths/links keys in cshift.json.
