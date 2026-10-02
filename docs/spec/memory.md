# Memory

CShift has no garbage collector. Values are copied; strings, arrays, closures and the blocks behind the standard
library's containers are freed by automatic reference counting (ARC); everything else is memory that the program manages
itself, in [`unsafe`](#unsafe) code.

## Values and references

A **value type** (the numbers, `bool`, `char`, enums, structs, unions, `Fixed<T, N>`, `Optional<T>`, `Error<T>`,
slices, pointers) is copied when it is assigned, passed by value, returned, stored in an array or captured by a lambda.
A struct is copied field by field: a field of a value type is copied along, a field of a reference type is shared.

A **reference type** (`string`, arrays, `Action`/`Func` with captures, `SharedPtr<T>`, `Thread`) is a pointer to a
block on the heap. A copy refers to the same block. The kinds of all types are listed in
[types](types.md#kinds-of-types).

The containers of the standard library (`List<T>`, `Dictionary<K, V>`, `StringBuilder`, ...) are structs whose fields
refer to arrays, so copies of a container share its contents:

```csharp
var a = List<int>.Create();
var b = a;
b.Add(1);               // a.Count() is 1 too
var c = a.Clone();      // an independent copy
```

Strings cannot be changed, so sharing them is never visible (`s += "x"` makes a new string).

## Reference counting

Every block of a reference type has a count of the references to it. Storing a reference (in a variable, a field, an
array element, a captured copy) increments it, and overwriting or giving up a reference decrements it; the block, and
the references it holds itself, are released when the count reaches 0. A local variable gives up its references when
its scope ends, a temporary value at the end of the statement, a global variable after `Main` returns.

* Freeing is **deterministic**: it happens at these points, never later and never in the background.
* There is **no cycle collection.** Blocks that refer to each other in a cycle (a closure that captures the
  container that holds it, for example) are never freed. Use indices into an array or a `List` instead of references
  that point back.
* The counts of strings, arrays and closures are **not atomic**; such values must not be shared between threads (the
  compiler enforces this, see [threads](#threads)). `SharedPtr<T>`, `Thread`, `Mutex<T>` have atomic counts.
* `cshiftc --arc-stats` prints the numbers of allocations and frees when the program ends.

## `ref` and `const ref`

A parameter is passed in one of three ways:

| Parameter | At the call | In the function |
|---|---|---|
| `T x` | any value that converts to `T` | a copy (for a reference type: another reference to the same block) |
| `ref T x` | `ref v`, where `v` is a variable, a field or an element of type `T` | an alias of `v`: reading and assigning `x` reads and assigns `v` |
| `const ref T x` | any value that converts to `T` | a read-only alias of the value (no copy); assigning to it or its fields is a compile error |

`ref` needs an exact type and a place that can be assigned: `ref 3` and `ref list.Get(0)` are compile errors. A
`ref` argument stays an alias for the call only: there are no `ref` locals, fields or results, so an alias cannot
outlive the call. A method called on a `const ref` parameter works on a copy of it.

An **interface** can be the type of a `ref` or `const ref` parameter (`void Draw(const ref IShape s)`): the function
takes any struct or union that implements it, without a copy, and calls the methods of the actual type. The function is
compiled once for each type it is called with (see [generics](declarations.md#generics)).

## `unsafe`

An **unsafe context** is the body of an `unsafe` function or method, an `unsafe { }` block or a statement with
`unsafe` before it (see [statements](statements.md#unsafe)). These operations are only allowed there:

* dereferencing a pointer: `*p`, `p->F`, `p[i]`;
* taking an address: `&x`;
* pointer arithmetic (`p + n`, `p - q`) and casts between pointers and to or from integers;
* `Memory.Allocate`, `Memory.Free`, `Memory.VolatileRead`, `Memory.VolatileWrite`;
* `s.CStr()`, `string.FromCStr(p)`, `SharedPtr<T>.Ptr()` and the other methods that hand out raw pointers.

Pointer types themselves, `null` and comparisons of pointers can be used anywhere, and so can calls of `unsafe`
functions and of C functions: the unsafe operations happen inside of them.

The compiler checks nothing about pointers: a pointer to a local variable that has gone out of scope, to a freed block
or to the inside of an array that was released is undefined behavior, like in C. `&x` of a local variable is valid as
long as the variable's scope lasts; `&` of a field or an element points into the struct or array that holds it.

**Manual memory.** `Memory.Allocate(n)` returns a block of `n` bytes that is not cleared (C's `malloc`), `Memory.Free(p)` frees
it; this memory is not counted. ARC values must not be stored in it (their counts would not be kept).

**Volatile access.** `Memory.VolatileRead(p)` and `Memory.VolatileWrite(p, v)` read and write a number, `bool`,
`char`, enum or pointer through `p` like a `volatile` access in C: each access happens, in the order of the program, and
none is merged with another or left out. This is what hardware registers and memory shared with interrupts need.

## Threads

A [thread function](declarations.md#thread-functions) runs on its own OS thread. It shares nothing with the thread that
started it except through its parameters and its result, and the compiler checks that this sharing is safe:

* A thread function cannot use **global variables**, directly or through the functions it calls. Constants are
  fine.
* Its **parameters** must be transferable: numbers, `bool`, `char`, enums; `string` (the thread gets its own copy);
  `ReadOnlySlice<T>` of transferable elements (the thread gets its own copy of the elements; arrays and slices
  convert to it); `SharedPtr<T>`, `Mutex<T>` and `Thread<T>` of thread-safe `T`; `Optional<T>`, `Error<T>` and
  structs made of these. Not allowed: `ref`/`const ref`, pointers, arrays, `Slice<T>`, `StringSlice`, the containers
  of the standard library and `Action`/`Func`.
* **Thread-safe** values (for `SharedPtr<T>` and the value of a `Thread<T>` that is passed on) are the transferable
  values without strings and slices: they are shared, not copied.
* The **result** has no restriction: it only moves from the thread to the caller of `Join()`.

`SharedPtr<T>` gives several threads one value with an atomic count; access to the value through `Ptr()` from several
threads needs its own synchronization. `Mutex<T>` holds a value behind a lock: `Lock()` returns a `MutexGuard<T>` that
holds the lock until it is disposed (`using`), and the value goes in and out as a copy that shares no reference count
with anything (`Memory.CopyForThread`). The standard library's threads API is in the
[language guide](../language/threading.md).

There are no other shared variables between threads, so a program without `unsafe` code and C calls has no data races.
