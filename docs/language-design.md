# A native, C#-like systems language

## 1. Goal

The language combines the expressiveness and readability of C# with native execution similar to C.

Goals:

* native executable programs
* no garbage collector
* no IL
* no JIT
* no mandatory runtime
* no header files
* no include guards
* no forward declarations
* automatic symbol and type resolution
* C#-like syntax
* structs instead of classes
* interfaces
* generics
* deterministic resource management
* direct C FFI
* the lowest possible language complexity

Core idea:

> C#-like productivity with native, C-like execution.

---

## 2. Basic principles

The language uses C#-like syntax, but deliberately does without central concepts of .NET and C++.

Not present:

* classes
* the CLR/.NET
* IL
* a JIT
* garbage collection
* header files
* include guards
* forward declarations
* a Rust-like ownership/borrow system
* move semantics
* copy/move constructors

The compiler produces native machine code, or native object files, directly.

---

## 3. Files and namespaces

Namespaces:

```csharp
namespace MyApp.Graphics;
```

Use:

```csharp
using MyApp.Graphics;
```

Types and functions can be defined in any source file.

The compiler analyzes the whole program and resolves symbols and types globally.

No header files or forward declarations are needed.

---

## 4. Structs

Structs are the language's central data type.

They are value types and have value semantics by default.

```csharp
struct Vec2
{
    float X;
    float Y;
}

var a = Vec2
{
    X = 10,
    Y = 20
};

var b = a;
```

`b` holds a copy of `a`.

Structs can contain other structs.

Using `new` with an ordinary struct does not mean an implicit heap allocation.

Where a value is actually placed — stack, register, inline inside another struct, and so on — is an implementation
decision made by the compiler.

---

## 5. Field visibility

There are no `public` or `private` keywords for fields.

Instead:

* a field name starting with `_` is private.
* every other field is public.

Example:

```csharp
struct Player
{
    int Health;
    int _internalState;
}
```

`Health` is public, `_internalState` is private.

---

## 6. No properties

The language has no properties.

There are only:

* fields
* methods

Getter and setter logic is written explicitly as a method:

```csharp
float GetLength()
{
    return ...
}
```

---

## 7. Struct inheritance

A struct can have exactly one other struct as its base type.

```csharp
struct Animal
{
    int Age;
}

struct Dog : Animal
{
    string Name;
}
```

Multiple inheritance of structs is not allowed.

A struct can additionally implement any number of interfaces:

```csharp
struct Dog : Animal, IAnimal, IDisposable
{
}
```

Struct inheritance is part of the memory layout. There is no hidden object hierarchy.

---

## 8. Interfaces

Interfaces define methods only.

They have:

* no fields
* no properties

Example:

```csharp
interface IDisposable
{
    void Dispose();
}
```

A struct can implement several interfaces.

Using an interface must never produce a hidden boxing allocation. Interfaces are therefore not value types:

* as a **generic constraint**, calls are resolved at compile time;
* as the type of a **`ref`/`const ref` parameter**, the function receives a pointer to the caller's struct (or, for
  `const ref`, to a copy on the caller's stack) and its method table — dynamic dispatch without an allocation. Such a
  parameter cannot be stored, so it cannot outlive the struct.

Collections of different structs use sum types (stored inline) instead of interface values.

---

## 9. Storage classes

The language distinguishes three basic categories:

### 1. Values

Ordinary structs and primitive types.

They have value semantics and are copied.

### 2. Managed dynamic data

For example:

* arrays
* strings
* dynamic containers
* resource handles

These have reference semantics and are managed by ARC.

### 3. Manual memory management

Explicit memory management is only allowed in `unsafe` code.

---

## 10. ARC

Managed dynamic data uses Automatic Reference Counting (ARC).

Copying a managed reference increments the reference count.

Releasing one decrements it.

When the count reaches zero, the memory is freed.

Example:

```csharp
var a = new int[100];
var b = a;
```

`a` and `b` reference the same array.

Primitive values and ordinary structs have no reference count.

ARC is deterministic and is not garbage collection.

---

## 11. Value copy and reference copy

Structs are copied in full:

```csharp
var b = a;
```

Managed dynamic data, by contrast, is copied as a reference:

```csharp
var b = a;
```

Here, only the reference is shared and its ARC count is incremented.

There is no implicit deep copy.

An independent copy is made explicitly:

```csharp
var b = a.Clone();
```

---

## 12. No implicit ownership system

The language has:

* no borrow checker
* no lifetime parameters
* no move semantics
* no copy/move constructors
* no implicit ownership transfer

An ordinary struct assignment means a value copy.

For managed dynamic data, assignment means a reference copy.

---

## 13. `ref`

`ref` creates an explicit alias to existing storage.

No ownership transfer takes place.

```csharp
void Modify(ref Vec2 value)
{
    value.X += 1;
}
```

Call:

```csharp
Modify(ref position);
```

A `ref` alias must not outlive its target.

For example, a function must not return a reference to a local variable whose scope is already ending.

`ref` describes aliasing, not ownership.

---

## 14. Resources and `IDisposable`

Resources are not the same thing as memory.

Resources can be, for example:

* files
* sockets
* mutexes
* operating-system handles
* GPU resources
* memory mappings

The standard interface is:

```csharp
interface IDisposable
{
    void Dispose();
}
```

`Dispose()` is an ordinary method.

There is no general ownership system for resources.

---

## 15. Copyable resource handles

A resource struct holds a managed reference to the actual resource.

For example:

```text
File
 ↓
managed handle
 ↓
OS file handle
```

Copying a resource struct copies the managed reference.

That lets several struct values reference the same resource.

No second OS handle is created.

---

## 16. Dispose semantics

`Dispose()` releases the resource for the current reference.

If other references to the same resource still exist, the underlying resource is kept alive.

Example:

```csharp
var a = File.Open("test.txt");
var b = a;

a.Dispose();
```

`b` still references the same resource.

The physical resource is only released once no valid references remain.

---

## 17. `using`

`using` guarantees that `Dispose()` is called when the scope is left.

That also holds for:

* `return`
* `break`
* `continue`
* an error propagated via `try`

With several nested `using` declarations, cleanup happens in reverse order.

Declaration form:

```csharp
using file = File.Open("test.txt");
```

---

## 18. Scoped `using`

There is also a block form:

```csharp
using (var file = File.Open("test.txt"))
{
    file.Write("Hello");
}
```

It has the same semantics as the declaration form.

`using` guarantees that `Dispose()` is called, not necessarily that the underlying resource is destroyed immediately,
if other references still exist.

---

## 19. Restrictions on copying resources

Copying a resource struct must never:

* create a second OS handle
* create an implicit copy of the resource
* trigger an ownership transfer
* create a hidden move

It stays an ordinary struct copy sharing the managed resource.

---

## 20. Manual memory management

Manual memory management is only allowed inside `unsafe`.

Example:

```csharp
unsafe
{
    var memory = Memory.Allocate(1024);

    // ...

    Memory.Free(memory);
}
```

Manually allocated memory is not part of ARC.

The programmer is responsible for freeing it.

---

## 21. Arrays

Arrays are managed dynamic data.

They have:

* reference semantics
* ARC
* a fixed length once created

```csharp
var a = new int[10];
var b = a;
```

`a` and `b` reference the same array.

An independent copy is made explicitly:

```csharp
var b = a.Clone();
```

---

## 22. Strings

Strings are:

* immutable
* managed by ARC
* UTF-8

Modifying one produces a new string.

---

## 23. `Error<T>`

`Error<T>` is a built-in type that holds either a successful value of type `T`, or an error.

Example:

```csharp
Error<File> OpenFile(string path)
{
    ...
}

var result = OpenFile("test.txt");

if (result is File file)
{
    file.Read();
}

if (result is error e)
{
    // error: e.Message, e.Code
}
```

`Error<T>` is not a condition (`if (result)`, `!result` are errors): `is error e` tests for a failure, `is T v` for
a success. `is not` negates a pattern; `if (result is not File file) return;` makes `file` available after the `if`.

---

## 24. `try`

`try` propagates `Error<T>` automatically.

```csharp
var file = try OpenFile("test.txt");
```

If there is an error, the current function returns immediately with that error.

The calling function must return a compatible `Error<T>` type.

Example:

```csharp
Error<string> ReadConfig()
{
    var file = try OpenFile("config.txt");
    var text = try file.ReadAllText();

    return text;
}
```

`try` only works with `Error<T>`.

---

## 25. `Optional<T>`

`Optional<T>` represents a value that may or may not be present.

Example:

```csharp
var result = FindUser(42);

if (result is User user)
{
    user.Login();
}

if (result == null)
{
    // absent
}
```

`Optional<T>` is not a condition either: it is tested with `is T v` or compared with `null`.

`try` must not be used with `Optional<T>`.

---

## 26. Nested `Error`/`Optional` types

The following combinations are not allowed:

```text
Error<Error<T>>
Optional<Error<T>>
Optional<Optional<T>>
```

`Error<Optional<T>>` is allowed, for an operation that can fail or find nothing (a lookup in a database or a file).
Like every `Error<T>`, it cannot be used as a condition (`if (r)`, `!r`); the code has to say which case it
means (`r is error e`, `r is T v`, `r is Optional<T> o`, `try r`). This keeps errors and optional values unambiguous.

---

## 27. Generics

Generics use C#-like syntax:

```csharp
struct Pair<T>
{
    T First;
    T Second;
}

T Max<T>(T a, T b)
{
    ...
}
```

The compiler uses monomorphization.

A native specialization is generated for every type combination that's actually used.

For example:

```text
Max<int>
Max<double>
```

produce their own native implementations.

There is no generic runtime mechanism.

---

## 28. Generic constraints

Generic types can be constrained via interfaces:

```csharp
T Max<T>(T a, T b)
    where T : IComparable<T>
{
    ...
}
```

The compiler checks the required operations at compile time.

The resulting specialization is fully native.

---

## 29. Enums

Enums always have an explicit integer base type.

```csharp
enum Color : uint8
{
    Red,
    Green,
    Blue
}
```

That makes their size and ABI representation deterministic.

---

## 30. No classes

The language has no classes and no general object hierarchy.

The central type categories are:

* structs
* interfaces
* enums
* primitive types
* arrays
* strings
* generic types

---

## 31. C FFI and ABI

The primary external ABI is the C ABI.

The goal is to be able to use practically any ordinary C library directly.

Example:

```csharp
extern "C" int strlen(char* str);

extern "C" Window* create_window(
    int width,
    int height
);
```

Supported:

* C functions
* C pointers
* C integer types
* floating-point types
* C structs
* C enums
* pointer + length
* callbacks
* global C symbols

---

## 32. C structs and layout

FFI structs have a defined native memory layout.

Example:

```csharp
struct Vec3
{
    float X;
    float Y;
    float Z;
}
```

For three `float32` fields, the layout is, for example:

```text
X: offset 0
Y: offset 4
Z: offset 8
size: 12
```

That lets the struct be passed directly to C functions.

---

## 33. FFI and `unsafe`

C FFI can use both safe and unsafe types.

Direct pointer operations and direct memory access need `unsafe`.

Example:

```csharp
unsafe
{
    char* text = ...
}
```

---

## 34. Build system

The compiler produces native object files, or native executable files.

The build system handles:

* compilation
* generics monomorphization
* optimization
* linking
* pulling in C and system libraries
* resolving FFI
* debug information

Libraries can be linked in, for example:

```text
link "sqlite3"
link "user32"
link "opengl"
```

---

## 35. Target picture

A complete small program might look like this:

```csharp
using System;

namespace Example;

Error<string> LoadFile(string path)
{
    using file = try File.Open(path);
    return try file.ReadAllText();
}

int Main()
{
    var text = try LoadFile("hello.txt");

    Console.WriteLine(text);

    return 0;
}
```

The program runs as a native program, without a GC, .NET, IL or a JIT.

Error handling goes through `Error<T>` and `try`.

Resources are handled deterministically via `using` and `IDisposable`.

---

## 36. Language philosophy

The language aims to have as small and practical a core as possible.

Programmers should be able to focus on their application without having to give up native control.

The central idea is:

> C#-like productivity with native, C-like execution.

---

# Types, expressions and control flow

## 37. Primitive types

The language has explicitly sized integers:

```text
int8
int16
int32
int64

uint8
uint16
uint32
uint64
```

Floating point:

```text
float32
float64
```

Other primitive types:

```text
bool
char
```

`char` is a UTF-8 code-unit type and corresponds to a `uint8`.

Type aliases for everyday programming:

```text
int    = int32
uint   = uint32
float  = float32
double = float64
```

The explicit types stay available for C FFI.

Integer arithmetic is checked by default.

Example:

```csharp
int x = int.MaxValue;
x = x + 1;
```

An overflow causes a runtime error.

An explicit `unchecked` mechanism exists for deliberately wanted wraparound.

---

## 38. `bool`

`bool` has exactly two values:

```text
true
false
```

Only `bool` may be used directly as a condition.

Allowed:

```csharp
if (x > 10)
{
}
```

Not allowed:

```csharp
if (x)
{
}
```

There is no implicit conversion from integers, pointers, `Error<T>`, `Optional<T>` or other types to `bool`.

---

## 39. Operators

### Arithmetic operators

```text
+
-
*
/
%
```

### Comparison

```text
==
!=
<
>
<=
>=
```

### Logic

```text
&&
||
!
```

### Bit operations

```text
&
|
^
~
<<
>>
```

### Assignments

```text
=
+=
-=
*=
/=
%=
&=
|=
^=
<<=
>>=
```

---

## 40. No `++` and `--`

The language has no `++` and `--` operators.

Instead of:

```csharp
i++;
```

you write:

```csharp
i += 1;
```

This removes the extra prefix/postfix semantics.

---

## 41. Operator precedence

Operator precedence follows C#:

```text
()
!
~

*
/
%

+
-

<<
>>

<
>
<=
>=

==
!=

&

^

|

&&

||

=
+=
-= ...
```

Parentheses can always be used:

```csharp
var x = (a + b) * c;
```

---

## 42. Control flow

### `if`

```csharp
if (health > 0)
{
    Update();
}
else
{
    Die();
}
```

A single statement is allowed without a block, but not another control statement (`if`, `while`, `do`, `for`,
`foreach`, `switch`, `using (...)`); `else if` is allowed:

```csharp
if (ready)
    Start();

if (a)
    if (b)        // error: a nested 'if' needs braces
        Start();
```

### `while`

```csharp
while (running)
{
    Update();
}
```

### `do`

```csharp
do
{
    Update();
}
while (running);
```

### `for`

```csharp
for (var i = 0; i < 10; i += 1)
{
    Print(i);
}
```

### `foreach`

```csharp
foreach (var item in items)
{
    Process(item);
}
```

---

## 43. `switch`

The language has a C#-like `switch`:

```csharp
switch (color)
{
    case Color.Red:
        Print("red");
        break;

    case Color.Green:
        Print("green");
        break;

    default:
        Print("other");
        break;
}
```

Pattern matching is also possible:

```csharp
switch (result)
{
    case Error<int> r:
        ...
}
```

---

## 44. `break` and `continue`

Loops support:

```csharp
break;
continue;
```

`break` ends the immediately surrounding loop, or the corresponding `switch`.

`continue` starts the next iteration.

Labels for `break` or `continue` are not provided.

---

## 45. `return`

An ordinary return:

```csharp
int Add(int a, int b)
{
    return a + b;
}
```

For `void`:

```csharp
void DoSomething()
{
    return;
}
```

`return` may be left out at the end of a `void` function.

---

## 46. Struct initialization

There are two basic forms.

### Default initialization

```csharp
var player = new Player();
```

Every field gets its default value.

Typical default values:

```text
int       → 0
float     → 0
bool      → false
pointer   → null
string    → null
Optional  → no value
```

### Initializer

```csharp
var player = Player
{
    Health = 100,
    Position = Vec2
    {
        X = 10,
        Y = 20
    }
};
```

The initializer writes the struct's fields directly.

---

## 47. No constructors

Structs have no constructors.

Not provided:

```csharp
new Player(100, 20)
```

Instead:

```csharp
Player
{
    Health = 100,
    Position = Vec2
    {
        X = 20,
        Y = 30
    }
}
```

More involved initialization goes through ordinary functions:

```csharp
Player CreatePlayer(int health)
{
    return Player
    {
        Health = health
    };
}
```

---

## 48. Functions

Free functions can be overloaded:

```csharp
void Print(int value)
{
}

void Print(string value)
{
}

void Print(float value)
{
}
```

The compiler picks the matching function based on the argument types.

A `static` keyword is not required for free functions.

Structs can have methods:

```csharp
struct Vec2
{
    float X;
    float Y;

    float Length()
    {
        return sqrt(X * X + Y * Y);
    }
}
```

---

## 49. Parameters

Parameters are passed by value by default:

```csharp
void Process(Vec2 position)
{
}
```

`ref` provides an explicit alias:

```csharp
void Move(ref Vec2 position)
{
    position.X += 1;
}
```

Call:

```csharp
Move(ref position);
```

There's also `const ref` for a read-only alias:

```csharp
float Length(const ref Vec2 value)
{
    return sqrt(value.X * value.X + value.Y * value.Y);
}
```

The three basic forms are thus:

```text
T           → a value copy
const ref T → a read-only alias
ref T       → a mutable alias
```

`const ref` passes no value and creates no copy. The function only receives an alias to the existing storage.

Inside the function, the referenced value must not be modified.

`const ref` is not an ownership concept.

---

## 50. No `out`

The language has no `out` parameters.

Not provided:

```csharp
bool TryParse(string text, out int value)
{
}
```

Instead, the built-in result types are used:

```csharp
Error<int> Parse(string text)
{
    ...
}
```

or:

```csharp
Optional<int> Parse(string text)
{
    ...
}
```

That keeps parameter semantics reduced to three cases:

```text
value
const ref
ref
```

and result values are modeled through ordinary return values, or `Error<T>` and `Optional<T>`.
