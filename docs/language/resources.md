← [Language guide](README.md)

# Resources and `using`

Not everything that needs cleanup is memory — files, sockets, mutexes, OS handles and the like are *resources*, and
ARC doesn't know when to release them. `IDisposable` and `using` give that a deterministic answer.

```csharp
interface IDisposable
{
    void Dispose();
}
```

A resource struct implements `IDisposable` and internally holds a managed reference to the actual resource, so
copying the struct shares the resource rather than duplicating it:

```csharp
var a = File.Open("test.txt");
var b = a;           // b references the same open file as a

a.Dispose();          // releases a's reference
// b still works: the underlying resource stays open until every reference is disposed
```

## `using`

`using` guarantees `Dispose()` runs when the scope is left — including via `return`, `break`, `continue`, or an
error propagated with `try`. Two forms are available:

```csharp
Error<string> Load(string path)
{
    using file = try File.Open(path);   // Dispose() runs when Load returns, however it returns
    return try file.ReadAllText();
}

using (var file = File.Open("test.txt"))
{
    file.Write("Hello");
}   // Dispose() runs here
```

With several nested `using` declarations, cleanup runs in reverse order — last acquired, first released.

Next: [Functions and function pointers](functions-and-delegates.md).
