# CShift language guide

A tour of CShift's language features, each explained briefly with common code examples. It is the friendlier
companion to the [design document](../language-design.md) (the rationale) and the [language status](status.md) (the
precise list of what's implemented, and the decisions the design leaves open). The library is described in
[../stdlib.md](../stdlib.md).

## Contents

1. [Basics](basics.md) — program structure, namespaces, variables, control flow, operators
2. [Structs](structs.md) — fields, visibility, initializers, methods, inheritance
3. [Interfaces and generics](interfaces-and-generics.md) — interfaces (constraints, parameters), sum types, generic structs/functions
4. [Enums](enums.md) — enums with an explicit base type
5. [Memory model](memory-model.md) — value vs. reference semantics, ARC, `ref`/`const ref`, `unsafe`
6. [Error handling](error-handling.md) — `Error<T>`, `Optional<T>`, `try`, `is`/`switch` patterns
7. [Threads](threading.md) — `thread`, `Thread`/`Thread<T>`, `SharedPtr<T>`, `Mutex<T>`
8. [Resources and `using`](resources.md) — `IDisposable`, deterministic cleanup
9. [Functions and function pointers](functions-and-delegates.md) — overloading, parameters, `Action`/`Func`, lambdas
10. [Arrays, strings and collections](arrays-strings-collections.md) — arrays, strings and interpolation, slices, `List`, `Dictionary`, indexers
11. [Constants and global variables](constants-and-globals.md) — `const`, globals, the compile-time evaluator
12. [C interop (FFI)](ffi-and-interop.md) — `extern "C"`, importing C headers
13. [Projects](projects.md) — `cshift.json`, building programs with more than one file
14. [Language status](status.md) — the complete list of what's implemented

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

Save this as `hello.csh` and build it with `cshiftc hello.csh -o hello --run`, or start a project with
`cshiftc new hello && cshiftc run hello`. See the [main README](../../README.md) for how to get or build `cshiftc` itself.
