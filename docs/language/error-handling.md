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

`Error<T>` (and `Optional<T>`, below) also behaves like a `bool` in a condition — `true` means "a value is present"
(except `Error<Optional<T>>`, [see below](#nesting-only-erroroptionalt)):

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

## Nesting: only `Error<Optional<T>>`

`Error<Error<T>>`, `Optional<Error<T>>` and `Optional<Optional<T>>` are disallowed. `Error<Optional<T>>` is allowed,
for a lookup that can fail *or* find nothing:

```csharp
Error<Optional<User>> FindUser(int id)
{
    if (!connected)
        return error("no connection");
    if (!exists)
        return null;            // succeeded, nothing found
    return user;                // succeeded with a value
}
```

Because it has two "no" cases, it **cannot be used as a condition**: `if (r)` and `!r` are compile errors (would they
mean "failed" or "found nothing"?). Say which one you mean:

```csharp
var r = FindUser(7);
if (r is User u)                // succeeded and found a user
    Show(u);
else if (r is Optional<User>)   // succeeded, found nothing
    Console.WriteLine("no such user");
else                            // failed
    Console.WriteLine("error: " + r.Message);

Optional<User> found = try FindUser(7);   // 'try' passes the error on and gives the Optional<T>
```

Next: [Threads](threading.md).
