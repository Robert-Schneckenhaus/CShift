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
As with any C toolchain, the C library and the linker files come from the system (Ubuntu/Debian):

    sudo apt install build-essential

(gcc startup files, libc6-dev, binutils). The libraries clang needs — libedit, libxml2, libzstd, zlib and libffi —
are present on most systems; otherwise:

    sudo apt install libedit2 libxml2 libzstd1 zlib1g libffi8

clang, libclang and the LLVM libraries live in the "toolchain" folder and are found by cshiftc itself. An existing
LLVM installation is neither needed nor used.

Contents
--------
cshiftc        the compiler
toolchain/     clang, libclang, LLVM libraries (do not modify)
README.md      language status, usage, the cshift.json project file
FFI.md         importing C headers (using Name from "header.h";), function pointers
BuildDesign.md, LanguageDesign.md

Your own C libraries: see FFI.md and the includePaths/libraryPaths/links keys in cshift.json.
