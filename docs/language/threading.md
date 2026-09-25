← [Language guide](README.md)

# Threads

A `thread` function runs on its own OS thread. It cannot be called directly - only `start`ed. `start f(args)`
does not run `f` there and then: it starts the thread and immediately returns a handle, `Thread` for a function
that returns `void`, `Thread<T>` for a function that returns `T`.

```csharp
thread int Square(int x)
{
    return x * x;
}

void Main()
{
    Thread<int> t = start Square(6);
    // ... the main thread can keep doing other work here ...
    Console.WriteLine(t.Join());   // waits for the thread and prints 36

    start Square(10);             // fire and forget - the handle is simply not kept

    int result = (start Square(5)).Join();   // parenthesize to chain a method right off 'start ...'

    Square(6);   // compile-time error: a 'thread' function can only be called through 'start'
}
```

`start` is only recognized directly in front of a call (`start Foo(...)`, `start Obj.Method(...)`) - it is a
*contextual* keyword, not a reserved word, so a variable, parameter or field can still be named `start`.

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

Its parameters are restricted, because the reference counts of strings, arrays and the built-in containers are not
atomic. A `thread` function's parameters may be:

* plain values: numbers, `bool`, `char`, enums;
* **strings**: the thread gets its **own copy** (a new block that only the thread owns and releases when it is done).
  Strings cannot be changed, so the copy behaves exactly like the original;
* [`SharedPtr<T>`](#sharedptrt) of a **thread-safe** `T` (plain values, `SharedPtr`s of thread-safe values, and
  `Optional<T>`/structs made of them) - the value is *shared*, so a string inside it is not allowed:
  `SharedPtr<string>` is an error;
* `Optional<T>`, `Error<T>` and structs made of the above (the strings in them are copied as well).

Never `ref`/`const ref`, a raw pointer, an array, a built-in container or `Action`/`Func`: copying those would race on
a reference count that was never meant to be touched from two threads at once (or, for a raw pointer or
`Action`/`Func`, silently alias data the other thread does not expect). A `Thread<T>` handle holds a `SharedPtr` to
the result, so it can be passed to another thread only if `T` is thread-safe (`Thread<int>` yes, `Thread<string>`
no). The return type has no such restriction - `Error<T>`, a string, anything - since the value only ever moves
from the thread to whoever calls `Join()`.

```csharp
thread int CountWords(string text)      // 'text' is the thread's own copy
{
    return text.Split(' ').Length;
}

Thread<int> t = start CountWords("one two three");
```

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
atomic). Its value must itself be thread-safe (no strings, arrays or containers inside) when it is passed to a
thread:

```csharp
var box = SharedPtr<int>.Create(41);

thread int ReadIt(SharedPtr<int> shared)
{
    return shared.Get() + 1;
}

void Main()
{
    Thread<int> t = start ReadIt(box);
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
