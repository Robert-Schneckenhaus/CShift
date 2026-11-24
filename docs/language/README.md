# CShift language guide

A tour of CShift's language features, each explained briefly with common code examples. It is the friendlier
companion to the [design document](../language-design.md) (the rationale) and the [language status](status.md) (the
precise list of what's implemented, and the decisions the design leaves open). The exact rules are in the
[language reference](../spec/README.md). The library is described in
[../stdlib.md](../stdlib.md).

## Contents

1. [Basics](basics.md) — program structure, namespaces, variables, control flow, operators
2. [Structs](structs.md) — fields, visibility, initializers, methods, inheritance
3. [Tuples](tuples.md) — `(int, string)`, `return (a, b);`, `var (x, y) = t;`, swapping, tuples as keys
4. [Interfaces and generics](interfaces-and-generics.md) — interfaces (constraints, parameters), sum types, generic structs/functions
5. [Enums](enums.md) — enums with an explicit base type
6. [Memory model](memory-model.md) — value vs. reference semantics, ARC, `ref`/`const ref`, `unsafe`
7. [Error handling](error-handling.md) — `Error<T>`, `Optional<T>`, `try`, `is`/`switch` patterns
8. [Threads](threading.md) — `thread`, `Thread`/`Thread<T>`, `SharedPtr<T>`, `Mutex<T>`
9. [Resources and `using`](resources.md) — `IDisposable`, deterministic cleanup
10. [Functions and function pointers](functions-and-delegates.md) — overloading, parameters, `Action`/`Func`, lambdas
11. [Arrays, strings and collections](arrays-strings-collections.md) — arrays, strings and interpolation, slices, `List`, `Dictionary`, indexers
12. [Constants and global variables](constants-and-globals.md) — `const`, globals, the compile-time evaluator
13. [C interop (FFI)](ffi-and-interop.md) — `extern "C"`, importing C headers
14. [Projects](projects.md) — `cshift.json`, building programs with more than one file
15. [Doc comments](doc-comments.md) — `///` and `//!`, tags, links, `cshiftc doc`
16. [Language status](status.md) — the complete list of what's implemented

## A first program

```csharp
using System;

struct Vec2
{
    float X;
    float Y;

    float Length() { return sqrt(X * X + Y * Y); }
}

int Main()
{
    var v = Vec2 { X = 3, Y = 4 };
    Console.WriteLine(v.Length());   // 5
    return 0;
}
```

Save this as `hello.cshift` and build it with `cshiftc hello.cshift -o hello --run`, or start a project with
`cshiftc new hello && cshiftc run hello`. See the [main README](../../README.md) for how to get or build `cshiftc` itself.
