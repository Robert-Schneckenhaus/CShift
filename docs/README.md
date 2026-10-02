# CShift documentation

| Document | For |
|---|---|
| [Installation](install.md) | what `cshiftc` needs on Windows and Linux, the packages per distribution |
| [Language guide](language/README.md) | learning the language: a tour with examples, chapter by chapter |
| [Language status](language/status.md) | what is implemented, and the decisions the design leaves open |
| [Standard library](stdlib.md) | `List`, `Dictionary`, `File`, `Path`, `Math`, `Random`, threads, `Mutex`, ... |
| [C interop: importing headers](ffi.md) | `using X from "header.h"`, type mapping, callbacks, structs by value |
| [The Amiga: the m68k backend](amiga.md) | AmigaOS programs: `--target m68k-amigaos`, libraries from SFD files, the NDK, `Amiga.Hardware` |
| [Debugging](debugging.md) | `-g`: breakpoints, stepping and call stacks with gdb and lldb |
| [Projects and the build](build.md) | `cshift.json`, `cshiftc build/run/new`, ideas for a build in CShift |
| [The compiler](compiler.md) | how `cshiftc` works, the bootstrap, tests, dependencies |
| [Language design](language-design.md) | the original design document: goals and rationale |

The documentation is also a website with search and the reference of every type and function of the standard
library: https://robert-schneckenhaus.github.io/CShift/ (made by [site/](../site/README.md) at every release).

The compiler's sources are described in [selfhost/README.md](../selfhost/README.md); open work is in
[Todo.md](../Todo.md), the changes of each release in [CHANGELOG.md](../CHANGELOG.md).
