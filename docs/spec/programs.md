# Programs and names

## Programs and files

A program is a set of source files that are compiled together: the files given to the compiler, or the `sources` of a
[project](../language/projects.md) (`cshift.json`), plus the standard library. All files see each other's
declarations; there are no header files, and declarations can be used before (and in other files than) their
definition.

```ebnf
CompilationUnit = { TopLevel } ;
TopLevel        = NamespaceDecl | UsingDecl | ImportDecl | LinkDecl
                | StructDecl | InterfaceDecl | UnionDecl | EnumDecl | ErrorEnumDecl
                | FunctionDecl | ConstDecl | GlobalDecl ;
```

The top level of a file holds declarations only; statements are only allowed in function bodies.

## Namespaces

```ebnf
NamespaceDecl = 'namespace' QualifiedName ';' ;
QualifiedName = Identifier { '.' Identifier } ;
```

A file has at most one namespace declaration (a second one is a compile error); it applies to every declaration of the
file, wherever it appears. A file without one declares in the **global namespace**. Every prefix of a namespace is a
namespace too (`A.B.C` makes `A` and `A.B`). The declarations of a namespace can come from any number of files.

The standard library's main namespace is `System`; its other namespaces are `Math`, `String`, `Char`, `FastTrig` and
(for AmigaOS) `Amiga`. The built-in types and the interfaces `IDisposable`, `IComparable<T>`, `IEquatable<T>` and
`IHashable` are in the global namespace.

## `using`

```ebnf
UsingDecl = 'using' QualifiedName ';' ;
```

`using N;` makes the declarations of the namespace `N` visible in the file without qualification. It applies to the
whole file and does not include nested namespaces (`using A;` does not make `A.B.X` visible as `X`).

## Name lookup

A name `X` in a file with the namespace `N` is looked up in this order:

1. local variables and parameters, innermost scope first, then the members of the enclosing struct (in a method);
2. the file's namespace `N`, then the global namespace;
3. the namespaces of the file's `using` declarations.

* **Types and constants:** the first place that declares the name wins. Among `using` namespaces, the first `using`
  (in the order of the file) wins; there is no ambiguity error.
* **Functions:** the functions of all visible places with that name form one overload set (the file's namespace, the
  global namespace and every `using` namespace); overload resolution picks the best one. Two candidates that match
  equally well make the call ambiguous (a compile error) - qualify the name to choose one (`A.F()`).
* A **qualified name** `N.X` names the declaration `X` of the namespace `N` directly; a struct's static members are
  named the same way (`List<int>.Create()`, `int.MaxValue`). A name that is both a variable and a type (`Color Color`)
  means the variable when the member after the `.` belongs to its value, otherwise the type (C#'s rule).

## Importing C headers

```ebnf
ImportDecl = 'using' QualifiedName 'from' StringLiteral ';' ;
LinkDecl   = 'link' StringLiteral [ ';' ] ;
```

`using Gl from "GL/gl.h";` reads the C header with libclang and makes its functions, structs, enums, constants and
macros available in the namespace `Gl` (qualified, `Gl.glClear(...)`, or after `using Gl;`). The same namespace name
must always import the same header. `link "m";` links the library `libm`. The rules of the import (the mapping of the
C types, callbacks, structs by value, include paths) are in [C interop](../ffi.md); `extern "C"` declarations are in
[declarations](declarations.md#extern-c-functions).

## The entry point

A program has exactly one function named `Main` (outside of the standard library) with one of these forms:

```csharp
void Main()
int Main()                    // or any other integer type: the exit code
int Main(string[] args)       // the command-line arguments, without the program's name
Error<int> Main()             // also with string[] args
```

`void Main()` ends with exit code 0. A failure returned from `Error<int> Main()` (also by `try`) prints
`error: <message>` to stderr and ends with exit code 1. Another return type is a compile error, and so is a program
without `Main` or with two of them. Before `Main` runs, the global variables are initialized (see
[declarations](declarations.md#global-variables)); after it returns, their heap memory is released.

## Compilation model

* **Whole program:** the compiler sees all files at once, so the order of the files and of the declarations does not
  matter, except for the initialization of global variables (in the order of the files and, within a file, of the
  declarations).
* **Generics** are instantiated for every combination of type arguments that the program uses; a generic function
  that is never used is still checked for what can be checked without its type arguments.
* **The standard library** is compiled with every program; only what the program uses ends up in the executable.
* **Checks:** the compiler reports all errors it finds (up to 50) and generates nothing if there is one.
  `cshiftc check` only reports them.
