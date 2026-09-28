← [Language guide](README.md)

# Basics

## Program structure

A CShift program is one or more `.csh` files compiled together. There are no header files and no forward
declarations — types and functions can be used before they're defined, in the same file or a different one, because
the compiler resolves the whole program at once.

```csharp
using System;

int Main()
{
    Console.WriteLine("Hello, World!");
    return 0;
}
```

`Main` is the entry point. It can be `int Main()`, `void Main()`, `int Main(string[] args)`, or return
`Error<int>` (see [error handling](error-handling.md)).

## Namespaces

```csharp
namespace MyApp.Graphics;   // one file-scoped namespace per file, at the top

using MyApp.Graphics;       // pulls a namespace's names into scope
using System;                // the standard library's main namespace
```

Name lookup checks the current file's own namespace and the global namespace first, then `using` namespaces — the
same order as C#.

## Comments

```csharp
// a line comment
/* a block comment */
```

## Variables

```csharp
int count = 0;
var name = "Ann";        // the type is inferred from the initializer
string title;             // starts as null
double ratio = 2.5;
bool ready = true;
```

`var` needs an initializer; without one, write out the type. See [constants and globals](constants-and-globals.md)
for `const` and top-level variables.

## Primitive types

```text
int8  int16  int32  int64      uint8  uint16  uint32  uint64
float32  float64
bool
char                             // a UTF-8 code unit, same size as uint8
```

Aliases for everyday use: `int` = `int32`, `uint` = `uint32`, `float` = `float32`, `double` = `float64`. The
explicitly sized names stay useful for FFI (see [C interop](ffi-and-interop.md)) and for being precise about a
type's range. `nint`/`nuint` are pointer-sized integers (like C#'s `IntPtr`/`UIntPtr`).

Integer arithmetic is checked by default: an overflow, a division by zero, or an out-of-range array/string access
ends the program with a panic rather than silently producing a wrong value.

```csharp
int x = int.MaxValue;
x = x + 1;              // panics: integer overflow

unchecked
{
    x = x + 1;           // wraps instead, no panic
}
```

`unchecked { ... }` and `unchecked(expr)` switch the check off for a block or an expression. To switch it off for a
whole program, compile with `--unchecked` (it applies to the files given to the compiler) or put `"unchecked": true`
into `cshift.json` (the whole project). Division by zero and array/string bounds stay checked either way, and so does
the standard library.

A panic prints its reason and where it happened, then ends the program with exit code 101. An index check also
shows the index and the length. When a function of the standard library rejects its arguments (`List.Get` with an
index out of range, `Dictionary.Get` with a missing key, ...), the panic also shows where the program called it:

```text
panic: array index out of range (index 5, length 3)
  at src/Game/World.csh:482:21 in World.GetTile

panic: List index out of range (index 4, count 2)
  at stdlib/list.csh:58:30 in System.List<int32>.Get
  called from src/Game/Party.csh:77:31 in Party.Member
```

The same goes for `Environment.Panic("message")`. The path is the one the compiler was given; in a project it is
relative to the project folder.

## Operators

Arithmetic (`+ - * / %`), comparison (`== != < > <= >=`), logic (`&& || !`), bitwise (`& | ^ ~ << >>`), and the usual
compound assignments (`+= -= *= /= %= &= |= ^= <<= >>=`) all work as in C#, with the same precedence. There is no
`++`/`--`; write `i += 1` instead. The conditional operator `cond ? a : b` is available.

Only `bool` can be used as a condition — there's no implicit conversion from `int`, a pointer, `Error<T>` or `Optional<T>` to
`bool`:

```csharp
if (count > 0)   // fine
{
}

if (count)        // error: not a bool
{
}
```

## Control flow

```csharp
if (health > 0)
    Update();
else
    Die();

while (running)
    Update();

do
    Update();
while (running);

for (var i = 0; i < 10; i += 1)
    Print(i);

foreach (var item in items)     // arrays, strings, and structs with Count()/Get(int) like List<T>
    Process(item);

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

A body may be a single statement without braces, but **not another control statement** (`if`, `while`, `do`, `for`,
`foreach`, `switch`, `using (...)`): nesting needs braces. `else if` chains are fine.

```csharp
foreach (var item in items)
    if (item.Done)             // error: a nested 'if' needs braces
        Count();

foreach (var item in items)
{
    if (item.Done)
        Count();
}
```

A `switch` over an enum (or a [union](interfaces-and-generics.md#sum-types)) without `default:` must handle every
member; a missing one is a compile error, so adding a member shows every switch that has to handle it. Members that
share a value count as handled together.

`switch` also supports pattern matching for `Error<T>`/`Optional<T>` — see [error handling](error-handling.md).
`break` exits the nearest loop or `switch`; `continue` starts the next iteration. Neither takes a label.

Next: [Structs](structs.md).
