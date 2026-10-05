← [Language guide](README.md)

# Memory model

CShift has no garbage collector and no borrow checker. Instead it uses three simple, predictable rules.

## 1. Values are copied

Ordinary structs and primitive types have value semantics. Assigning or passing one copies it:

```csharp
var a = Vec2 { X = 1, Y = 2 };
var b = a;
b.X = 99;   // a.X is still 1
```

Fixed-size arrays ([`Fixed<T, N>`](arrays-strings-collections.md#fixed-size-arrays-fixedt-n)) are values too: their
elements are stored inline and copied along.

## 2. Managed dynamic data uses ARC

Arrays, strings, and the built-in containers (`List<T>`, `Dictionary<K,V>`, …) have reference semantics and are
managed by Automatic Reference Counting: copying a reference increments a count, releasing one decrements it, and
the memory is freed once the count reaches zero.

```csharp
var a = new int[100];
var b = a;          // b references the same array as a; the ARC count is now 2
b[0] = 42;           // a[0] is also 42
```

This is deterministic — not garbage collection. There's no cycle collector, so avoid reference cycles between
structs that hold managed data (the same rule as with `shared_ptr` in C++, or `Rc` in Rust).

An independent copy is always explicit:

```csharp
var b = a.Clone();
```

`--arc-stats` (a `cshiftc`/`cshc` flag) prints the number of heap allocations and frees when the program exits, so
you can check that everything balances.

The compiler counts only where it has to. At the last use of a local variable - `return list;`, `var b = a;` when
`a` is not read again, the fields of `return Point { Name = name }` - the reference is handed on instead of being
counted up and, at the end of the scope, down again. And `text += ...` on a local variable writes in place when no
other variable, slice or parameter refers to the string ([strings](arrays-strings-collections.md#strings)). Neither
changes what a program does: a value that is still used elsewhere is never given away or changed.

## 3. Manual memory management needs `unsafe`

```csharp
unsafe
{
    var memory = Memory.Allocate(1024);
    // ...
    Memory.Free(memory);
}
```

Memory from `Memory.Allocate` is not tracked by ARC — you're responsible for freeing it, exactly like `malloc`/`free`
in C. This mechanism, plus raw pointers, is also what makes [C interop](ffi-and-interop.md) work.

`Memory.VolatileRead(p)` and `Memory.VolatileWrite(p, value)` (also `unsafe`) read and write through a pointer to a
number, `bool`, `char`, enum or pointer like `volatile` in C: every access happens, in program order, and none is
merged with another or left out. That is what hardware registers need (memory-mapped I/O) and memory that an interrupt
changes:

```csharp
unsafe
{
    var color0 = (uint16*)0xDFF180;            // Amiga: background color register
    for (var i = 0; i < 4096; i += 1)
        Memory.VolatileWrite(color0, (uint16)i); // 4096 writes, not one
}
```

## `ref` and `const ref`

Parameters are passed by value by default (a copy for a struct, a shared reference for managed data). `ref` creates
an explicit, mutable alias to existing storage — not an ownership transfer:

```csharp
void Move(ref Vec2 position)
{
    position.X += 1;
}

Move(ref player.Position);
```

`const ref` is a read-only alias — no copy, but the callee can't modify it:

```csharp
float Length(const ref Vec2 value)
{
    return sqrt(value.X * value.X + value.Y * value.Y);
}
```

So a parameter is one of exactly three things:

```text
T           a value copy
const ref T a read-only alias
ref T       a mutable alias
```

A `ref` alias must never outlive what it points to — for example, a function can't return a `ref` to one of its own
local variables.

## Pointers and `unsafe`

Raw pointers (`T*`), the address-of operator `&`, dereferencing `*`, and pointer arithmetic are all available, but
only inside an `unsafe` block or function — the same idea as C#'s `unsafe`:

```csharp
unsafe
{
    int value = 42;
    int* p = &value;
    *p = 100;           // value is now 100

    char* text = someString.CStr();   // a raw, NUL-terminated pointer into the string
}
```

`unsafe` also works on a whole function or method, and before a single statement (a variable it declares stays
visible after it):

```csharp
unsafe void Render()               // the whole body is unsafe
{
    uint32* row = _pixels;
    ...
}

struct Canvas
{
    static unsafe void Clear(uint32* p, int n) { ... }
}

unsafe Memory.Free(_pixels);        // just this statement
unsafe uint8* bytes = (uint8*)data; // bytes can be used afterwards (in unsafe code)
```

Pointers show up constantly at the C boundary — see [C interop](ffi-and-interop.md) for how C's own pointer types map
to CShift.

Next: [Error handling](error-handling.md).
