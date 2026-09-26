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

`is error e` matches only a failure and binds the result, so the error can be used under a name (it works for every
`Error<T>`, including `Error<void>`, and as `case error e:` in a `switch`; `is error` without a name just tests):

```csharp
if (OpenFile(path) is error e)
    Console.WriteLine($"failed ({e.Code}): {e.Message}");

switch (Parse(text))
{
    case int value:
        Use(value);
        break;
    case error e:
        Report(e.Message);
        break;
}
```

A pattern of the value's own type (`result is Error<File> r`) would always match, so it is a compile error.

`Error<T>` is **not a condition**: `if (result)`, `!result`, `result && ...` and `result ? a : b` are compile errors,
because they would hide what is tested. Write `is error e` (failed) or `is T v` (succeeded):

```csharp
if (Save() is error e)                    // Error<void>: 'is error' is the only test
    Console.WriteLine("cannot save: " + e.Message);

bool ok = Parse(text) is not error;       // just the outcome
```

### `is not`

`is not` negates any pattern: `x is not T`, `x is not error`. For optional values (and anything else that can be
compared with `null`), `x is null` and `x is not null` mean `x == null` and `x != null`.

A binding of `is not` is assigned where the pattern *did* match, so it is used as a guard: `if (x is not T v)` makes
`v` available in the `else` branch, and after the `if` when its branch cannot complete (`return`, `break`,
`continue`):

```csharp
int Port(string text)
{
    if (text.ParseInt() is not int port)
        return 80;               // 'port' is not assigned here
    return port;                 // ... but here it is
}
```

A binding under `is not` is only allowed as the whole condition of an `if`.

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

`Optional<T>` is not a condition either (`if (found)` and `!found` are compile errors): test it with `is T v` or
compare it with `null` (`found == null`, `found != null`). `try` must not be used with `Optional<T>`.

## Error enums: typed error codes

An error enum declares the codes a function can fail with:

```csharp
error FileError
{
    NotFound,          // 1
    Denied = 13,
    Locked             // 14
}
```

It is an enum with base type `int32`, but its members count from **1**: code 0 means "no specific code" (the code of
`error("text")` and of a default result), so `= 0` is a compile error. A member converts implicitly to `int` (`int c =
FileError.Denied;`, `e.Code == FileError.Denied`); the other way needs a cast, as for every enum.

`error(...)` takes a member as the code; without a message, the message is the member's name:

```csharp
return error(FileError.NotFound);                  // Message "NotFound", Code 1
return error("no access to " + path, FileError.Denied);
```

This works in any function returning `Error<T>` (the code is then an `int`). A result can also say which codes it
has: **`Error<T, E>`**, or short **`E<T>`**:

```csharp
FileError<string> Read(string path)                // = Error<string, FileError>
{
    if (!File.Exists(path))
        return error(FileError.NotFound);
    if (File.ReadAllText(path) is not string text)   // a plain Error<string>: its codes are ints, so translate
        return error("cannot read " + path, FileError.Denied);
    return text;
}
```

On an `Error<T, E>`, `e.Code` is an `E`, and the code can be matched directly:

```csharp
if (Read(path) is FileError code)                  // failed; 'code' is the FileError
    Console.WriteLine("failed with " + ((int)code).ToString());

switch (Read(path))
{
    case string text:
        Show(text);
        break;
    case FileError.NotFound:                       // failed with this code
        CreateDefault();
        break;
    case error e:                                  // any other failure
        Console.WriteLine(e.Message);
        break;
}
```

The rules:

* An `Error<T, E>` only takes codes of `E`: `error(E.X)`, `error("text", E.X)` or `error("text")` (code 0), not
  `error("text", 5)`.
* `Error<T, E>` converts implicitly to `Error<T>` (the code becomes an `int`), never the other way.
* `try` passes an error on unchanged: from `Error<T, E>` into a function returning `Error<U, E>` or `Error<U>`. An
  error with other codes must be translated: `if (r is error e) return error(e.Message, FileError.Denied);`.
* An error enum is not a result value: `Error<FileError>` is a compile error, and so is `return FileError.NotFound;`
  in a function returning `Error<int>` (it would be a success with the value 1).
* `Error<void, E>` (`E<void>`) and `Error<Optional<T>, E>` work like their plain forms.

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

Like every `Error<T>` it is not a condition (with two "no" cases, `!r` could not even say whether it means "failed" or
"found nothing"). Say which one you mean with `is error e`, `is T v` or `is Optional<T> o`:

```csharp
var r = FindUser(7);
if (r is error e)               // failed
    Console.WriteLine("error: " + e.Message);
else if (r is User u)           // succeeded and found a user
    Show(u);
else                            // succeeded, found nothing
    Console.WriteLine("no such user");

Optional<User> found = try FindUser(7);   // 'try' passes the error on and gives the Optional<T>
```

Next: [Threads](threading.md).
