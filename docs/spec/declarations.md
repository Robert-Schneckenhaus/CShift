# Declarations

The top level of a file declares types, functions, constants and global variables. Every declaration can be preceded
by a [doc comment](../language/doc-comments.md).

## Visibility

There are no access modifiers. A **field or method** whose name starts with `_` is private to its struct: only the
methods of that struct can use it (not the methods of a derived struct, not an initializer outside of it).
Everything else is visible to the whole program. Top-level names with `_` are ordinary names (the convention marks
them as internal).

## Structs

```ebnf
StructDecl  = 'struct' Identifier [ TypeParams ] [ ':' Type { ',' Type } ] { Constraint } '{' { Member } '}' ;
Member      = Field | Method ;
Field       = Type Identifier ';' ;
Method      = { 'static' | 'unsafe' | 'thread' } Type Identifier [ TypeParams ] '(' [ Params ] ')' { Constraint }
              ( Block | ';' ) ;
```

A struct is a value type made of fields (see [types](types.md#structs)). Fields have no initializers; a field gets its
[default value](types.md#default-values) unless an initializer (`S { F = x }`) sets it. There are no constructors,
destructors, properties or static fields: a `static` method that returns the struct takes the place of a constructor.

**Methods.** A method without `static` has the struct as `this`: the fields and methods are used by their names (or as
`this.F`), and a method can change the fields of the value it is called on (the variable, the array element, the
field). A `static` method has no `this` and is called on the type (`S.Make()`). Methods of the same name can be
overloaded. A method called on a `const ref` parameter runs on a copy, so it cannot change the caller's value.

**Base struct and interfaces.** The list after `:` names at most one base struct (first) and any number of
interfaces. The base struct's fields come first in the layout, and the derived struct has its fields and methods; a
method with the same name and parameters hides the base's. A derived struct converts implicitly to its base (the
base part is copied); there is no conversion back and no virtual dispatch. For every interface, the struct must have
a method with the same name, parameter and result types (a compile error otherwise).

A struct cannot contain itself, directly or through the fields of other structs (`Fixed` included); an array, a
`List` or a slice of it is fine.

## Interfaces

```ebnf
InterfaceDecl   = 'interface' Identifier [ TypeParams ] '{' { InterfaceMethod } '}' ;
InterfaceMethod = Type Identifier '(' [ Params ] ')' ';' ;
```

An interface lists methods without bodies; it has no fields. A struct or union implements it by listing it after `:`
and having the methods. Interfaces are used as [constraints](#constraints) and as the types of `ref`/`const ref`
parameters (see [types](types.md#interfaces)).

## Unions

```ebnf
UnionDecl = 'union' Identifier [ ':' Type { ',' Type } ] '{' Type { ',' Type } [ ',' ] '}' ;
```

A union holds a value of exactly one of its member types, stored inline with a tag; its size is that of the largest
member plus the tag. The members are value types (structs, numbers, strings, ...), each at most once, and at least
one. The interfaces after `:` must be implemented by every member; their methods can then be called on the union
(dispatched on the tag, on the value inside the union), the union satisfies constraints on them and can be passed to
`ref`/`const ref` parameters of them.

```csharp
union Shape : IShape { Circle, Rect }

Shape s = Circle { R = 1.0 };   // a member converts to the union
if (s is Circle c) ...          // takes it out (a copy)
```

A `switch` over a union without `default` must have a `case` for every member.

## Enums

```ebnf
EnumDecl   = 'enum' Identifier ':' Type '{' [ EnumMember { ',' EnumMember } [ ',' ] ] '}' ;
EnumMember = Identifier [ '=' ConstantExpression ] ;
```

The base type is required and must be an integer type. A member without a value has the value of the previous
member plus 1 (the first one 0). Values are [constant expressions](expressions.md#constant-expressions) of the base
type and may use earlier members and other constants (`Both = Read | Write`). Several members may have the same
value. Members are named qualified (`Color.Red`).

## Error enums

```ebnf
ErrorEnumDecl = 'error' Identifier '{' [ EnumMember { ',' EnumMember } [ ',' ] ] '}' ;
```

An error enum is an enum of error codes with the base type `int32`. Its members count from **1** (0 means "no
specific code"); `= 0` is a compile error. A member converts implicitly to `int`. `E<T>` is the result type
`Error<T, E>`, whose errors have codes of `E` (see [types](types.md#error) and [expressions](expressions.md#error-values)).

## Functions

```ebnf
FunctionDecl = { 'unsafe' | 'thread' } Type Identifier [ TypeParams ] '(' [ Params ] ')' { Constraint } Block
             | 'extern' '"C"' Type Identifier '(' [ Params ] [ ',' '...' ] ')' ( ';' | Block ) ;
Params       = Param { ',' Param } ;
Param        = [ 'ref' | 'const' 'ref' ] Type Identifier ;
```

A function at the top level belongs to the file's namespace. Functions can be called before their declaration and
from other files.

**Parameters** are passed by value (a copy of a value type, a shared reference for a reference type), as `ref` (a
mutable alias of the caller's variable, written `ref x` at the call) or as `const ref` (a read-only alias; the caller
passes any value). There are no default values, `out` parameters, named arguments or variable argument lists
(except for C functions). See [memory](memory.md#ref-and-const-ref).

**Result.** A function that does not return `void` must return a value on every path (a compile error otherwise);
`Error<void>` may also end without `return` (a success).

**Overloading.** Functions and methods with the same name and different parameter lists form an overload set. A call
picks the overload whose parameters fit the arguments with the cheapest conversions (an exact type before a
widening, an integer widening before a conversion to floating point, a literal fitting before a widening); two
equally good candidates are an ambiguous call (a compile error).

### Thread functions

```csharp
thread int Square(int x) { return x * x; }
Thread<int> t = start Square(6);
```

`thread` marks a function (or a `static` method) that runs on its own OS thread. It is only called with
[`start`](expressions.md#start), which returns a `Thread` (for `void`) or `Thread<T>`. A thread function cannot be
generic or variadic, cannot use global variables (also not through the functions it calls), and its parameters must
be transferable to another thread (see [memory](memory.md#threads)).

### Unsafe functions

`unsafe` before a function or method makes its whole body an [`unsafe`](memory.md#unsafe) context.

### extern "C" functions

`extern "C"` declares a C function: without a body, the function is linked from C (the standard C library, a library
named with `link` or `-l`); with a body, the function is defined in CShift with the C name, so C code can call it.
Only a C declaration may be variadic (`extern "C" int printf(char* format, ...);`). A string does not convert to
`char*`: pass `s.CStr()`, in `unsafe` code like every pointer. C headers can also be imported whole (see [programs](programs.md#importing-c-headers)).

## Generics

```ebnf
TypeParams = '<' Identifier { ',' Identifier } '>' ;
Constraint = 'where' Identifier ':' Type { ',' Type } ;
```

Structs, interfaces, functions and methods can have type parameters. Type arguments are written after the name
(`List<int>`, `Max<double>(a, b)`) or, for functions, inferred from the arguments (and from a lambda's result, see
[expressions](expressions.md#lambdas)). Every combination of type arguments that the program uses is compiled
separately (monomorphization); there is no boxing and no generic code at run time. `Fixed<T, N>` is the only type
with a number as a type argument.

### Constraints

`where T : I1, I2` requires every type argument for `T` to implement the interfaces (a compile error at the use
otherwise). In the body, a value of type `T` has the methods of its constraints and `ToString()`; other methods are a
compile error, also before the function is used. Operators on `T` (`==`, `<`, `+`, ...) are checked for every type
argument the function is used with. The numbers, `bool`, `char`, enums and `string` implement `IEquatable<T>`,
`IComparable<T>` (not `bool`) and `IHashable`.

## Constants

```ebnf
ConstDecl = 'const' Type Identifier '=' ConstantExpression ';' ;
```

A constant has a type of: a number, `bool`, `char`, `string`, an enum, or `ReadOnlySlice<T>` of these (a constant
slice). Its value is computed when the program is compiled (see
[constant expressions](expressions.md#constant-expressions)); an overflow, a division by zero or an index out of
range is a compile error there. `embed("file")` and `embed_filenames("pattern")` read files into constants (see
[expressions](expressions.md#embed)).

A top-level constant belongs to the file's namespace, can be used before its declaration and is checked even if
nothing uses it. A constant can also be declared in a function body (a local constant); it has no storage and cannot
be assigned. The type is required (`const var` is a compile error).

## Global variables

```ebnf
GlobalDecl = Type Identifier [ '=' Expression ] ';' ;
```

A global variable is declared at the top level with an explicit type (no `var`). Without an initializer it starts with
its default value. Initializers are arbitrary expressions; they run before `Main`, in the order of the files and of
the declarations in a file. The compiler checks that an initializer does not read a global that is initialized later
(or itself), also through the functions it calls; a global without an initializer can always be read. Globals are
released after `Main` returns. A [thread function](#thread-functions) cannot use them.
