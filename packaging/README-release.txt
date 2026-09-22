CShift @VERSION@ (Windows, 64-bit)
==================================

Installation
------------
1. Unpack this folder to a fixed location, e.g. C:\Tools\cshift.
2. Add the folder (containing cshiftc.exe) to PATH.
3. Open a new console and check:

       cshiftc --version
       cshiftc new hello
       cshiftc run hello

Nothing else is needed: the "toolchain" folder contains clang, lld, libclang, and the C headers and libraries
(MinGW-w64) that cshiftc needs for linking and for "using Name from "header.h";". cshiftc finds them itself.
An existing installation (MSYS2, LLVM, Visual Studio) is neither needed nor used.

Contents
--------
cshiftc.exe    the compiler
toolchain\     clang/lld/libclang, headers and libraries (do not modify)
README.md      language status, usage, the cshift.json project file
FFI.md         importing C headers (using Name from "header.h";), function pointers
BuildDesign.md, LanguageDesign.md

Your own C libraries: see FFI.md and the includePaths/libraryPaths/links keys in cshift.json.
VS Code extension (syntax highlighting): the vscode-extension folder in the repository.
