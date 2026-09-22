# CShift language guide

A tour of CShift's language features, each explained briefly with common code examples. This is a friendlier
companion to [../../LanguageDesign.md](../../LanguageDesign.md) (the terse design rationale) and the
["Language status"](../../README.md#language-status) table in the main README (the precise, up-to-date list of
what's implemented). If something here and the main README disagree, the main README wins.

## Contents

1. [Basics](basics.md) — program structure, namespaces, variables, control flow, operators
2. [Structs](structs.md) — fields, visibility, initializers, methods, inheritance
3. [Interfaces and generics](interfaces-and-generics.md) — interfaces, generic structs/functions, constraints
4. [Enums](enums.md) — enums with an explicit base type
5. [Memory model](memory-model.md) — value vs. reference semantics, ARC, `ref`/`const ref`, `unsafe`
6. [Error handling](error-handling.md) — `Error<T>`, `Optional<T>`, `try`, `is`/`switch` patterns
7. [Resources and `using`](resources.md) — `IDisposable`, deterministic cleanup
8. [Functions and function pointers](functions-and-delegates.md) — overloading, parameters, `Action`/`Func`
9. [Arrays, strings and collections](arrays-strings-collections.md) — arrays, strings, `List`, `Dictionary`, and more
10. [Constants and global variables](constants-and-globals.md) — `const`, globals, the compile-time evaluator
11. [C interop (FFI)](ffi-and-interop.md) — `extern "C"`, importing C headers
12. [Projects](projects.md) — `cshift.json`, building programs with more than one file

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
`cshiftc new hello && cshiftc run hello`. See the [main README](../../README.md#building-it) for how to build and
install `cshiftc` itself.
