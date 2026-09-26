# CShift documentation

| Document | For |
|---|---|
| [Language guide](language/README.md) | learning the language: a tour with examples, chapter by chapter |
| [Language status](language/status.md) | what is implemented, and the decisions the design leaves open |
| [Standard library](stdlib.md) | `List`, `Dictionary`, `File`, `Path`, `Math`, `Random`, threads, `Mutex`, ... |
| [C interop: importing headers](ffi.md) | `using X from "header.h"`, type mapping, callbacks, structs by value |
| [Projects and the build](build.md) | `cshift.json`, `cshiftc build/run/new`, ideas for a build in CShift |
| [The compiler](compiler.md) | how `cshiftc` works, the bootstrap and the frozen C++ compiler, tests, dependencies |
| [Language design](language-design.md) | the original design document: goals and rationale |

The compiler's sources are described in [selfhost/README.md](../selfhost/README.md); open work is in
[Todo.md](../Todo.md).
