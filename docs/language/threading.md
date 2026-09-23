← [Language guide](README.md)

# Threads

A `thread` function runs on its own OS thread. Calling it does not run it there and then - it starts the thread
and immediately returns a handle: `Thread` for a function that returns `void`, `Thread<T>` for a function that
returns `T`.

```csharp
thread int Square(int x)
{
    return x * x;
}

void Main()
{
    Thread<int> t = Square(6);
    // ... the main thread can keep doing other work here ...
    Console.WriteLine(t.Join());   // waits for the thread and prints 36
}
```

## Isolation

A `thread` function can only see its parameters and its return value - never global state:

```csharp
int counter = 0;

thread void Bad()
{
    counter += 1;   // compile-time error: a thread cannot use global state
}
```

This is checked transitively: a `thread` function may also not call a function that (directly or through further
calls) reads or writes a global variable.

Its parameters are restricted the same way `ref`/pointers are restricted elsewhere, but stricter: a `thread`
function's parameters must be plain value types (numbers, `bool`, `char`, enums, `Optional<T>` of one of those,
or a struct built only from these) or [`SharedPtr<T>`](#sharedptrt) - never `ref`/`const ref`, a raw pointer, a
string, an array, a built-in container, `Error<T>`, or `Action`/`Func`. Copying one of those across threads would
race on a reference count that was never meant to be touched from two threads at once (or, for a raw pointer or
`Action`/`Func`, silently alias data the other thread does not expect). Its return type has no such restriction -
`Error<T>`, a string, anything - since the value only ever moves from the thread to whoever calls `Join()`.

`thread` can mark a free function or a `static` struct method (it cannot see `this`, so it cannot mark an
instance method), and it cannot be generic or variadic.

## `Thread` / `Thread<T>`

| Member | Meaning |
| --- | --- |
| `Join()` | Waits for the thread and returns its result (nothing, for `Thread`). |
| `Cancel()` | Requests cancellation; does not wait. |
| `CancelAndWait()` | Requests cancellation and waits for the thread to finish. |
| `IsCompleted()` | True once the thread has finished - by returning, or after a cancellation request. |
| `IsCancelled()` | True once `Cancel()`/`CancelAndWait()` was called - the thread may still be running. |

`Thread<T>` additionally supports the non-blocking `is` pattern, the same way `Error<T>`/`Optional<T>` do:

```csharp
if (t is int value)
    Console.WriteLine(value);
```

`t is T value` is `true` only once the thread has completed *without* being cancelled - it never blocks. It is
`false` while the thread is still running, and `false` once cancellation was requested, even if the thread still
happened to return a value (see below); use `Join()` in that case to get the value regardless. There is no
`if (t)`/`if (!t)` conversion.

## Cancellation

`Cancel()` only sets a flag; a running thread notices it by reading the built-in `Thread.Cancelled`, which is
only available inside a `thread` function's own body:

```csharp
thread int CountTo(int limit)
{
    int i = 0;
    while (i < limit)
    {
        if (Thread.Cancelled)
            return i;   // still has to return an int
        i += 1;
    }
    return i;
}
```

A thread that returns a value must still return one when cancelled - there is no way to "not return". Returning
`Error<T>` is one natural way to report a cancellation as a failure, but nothing requires it; returning a partial
result, a default value, or anything else of type `T` is equally valid.

## `SharedPtr<T>`

A `SharedPtr<T>` is a box for one value of type `T` with an atomically reference-counted handle, safe to copy
between threads (unlike the reference counts of strings, arrays and the built-in containers, which are not
atomic and are exactly why those are not allowed as `thread` parameters):

```csharp
var box = SharedPtr<int>.Create(41);

thread int ReadIt(SharedPtr<int> shared)
{
    return shared.Get() + 1;
}

void Main()
{
    Thread<int> t = ReadIt(box);
    Console.WriteLine(t.Join());   // 42
}
```

* `SharedPtr<T>.Create(value)` moves `value` into a new box.
* `.Get()` returns a copy of the value.
* `.Ptr()` (`unsafe`) returns a raw `T*` to the shared value, for in-place access.
* `.IsNull()` is true for a `null` (default) `SharedPtr<T>`.

Only the reference count itself is thread-safe - concurrent access to the value through `.Ptr()` from more than
one thread needs its own synchronization, exactly like `std::shared_ptr` in C++.

Next: [Resources and `using`](resources.md).
