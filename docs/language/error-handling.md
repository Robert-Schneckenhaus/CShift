← [Language guide](README.md)

# Error handling

CShift has no exceptions. Instead, functions that can fail or that may not produce a value return one of two
built-in result types.

## `Error<T>`

Either a successful value of type `T`, or an error:

```csharp
Error<File> OpenFile(string path)
{
    if (!File.Exists(path))
        return error("file not found: " + path);
    return File.Open(path);
}
```

`error("message")` or `error("message", code)` creates the error case; `Error<T>` has `.Message` and `.Code`. Any
`T` converts implicitly to `Error<T>`, so `return someValue;` on success needs no wrapping.

Check the result with `is`, which binds the value on success:

```csharp
var result = OpenFile("test.txt");

if (result is File file)
{
    file.Read();
}
else
{
    Console.WriteLine("failed: " + result.Message);
}
```

`Error<T>` (and `Optional<T>`, below) also behaves like a `bool` in a condition — `true` means "a value is present":

```csharp
if (!result)
{
    // handle the error
}
```

## `try`

`try` unwraps an `Error<T>` and, on failure, immediately returns that same error from the current function — the
calling function must itself return a compatible `Error<...>`:

```csharp
Error<string> ReadConfig()
{
    var file = try OpenFile("config.txt");     // returns early from ReadConfig on error
    var text = try file.ReadAllText();
    return text;
}
```

This is CShift's equivalent of `?` in Rust or a chain of early returns in Go — it only works with `Error<T>`, never
with `Optional<T>`. `Error<void>` is a result with no payload (`Error<void> Save() { ...; return; }`); `try Save();`
just checks whether it succeeded.

In `int Main()`, an unhandled `try` failure prints `error: <message>` to stderr and exits with code 1 — which is why
short command-line programs can often write their whole body as a chain of `try` calls.

## `Optional<T>`

A value that may or may not be present — CShift's equivalent of a nullable value or `Option`/`Maybe`:

```csharp
Optional<User> FindUser(int id)
{
    // ...
    return null;         // or: return someUser;
}

var found = FindUser(42);

if (found is User user)
{
    user.Login();
}
```

Same `is`/bool semantics as `Error<T>`, but `try` must not be used with `Optional<T>`.

## Pattern matching in `switch`

```csharp
switch (result)
{
    case Error<int> r:
        Console.WriteLine("code " + r.Code.ToString());
        break;
}
```

## No nesting

`Error<Error<T>>`, `Error<Optional<T>>`, `Optional<Error<T>>` and `Optional<Optional<T>>` are all disallowed, so a
result is always unambiguous.

Next: [Threads](threading.md).
