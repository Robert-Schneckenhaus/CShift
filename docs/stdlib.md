# Standard library

← [Documentation](README.md)

The standard library is written in CShift itself (`stdlib/*.csh`) and embedded in the compiler. Only what a program
actually uses gets compiled (generics are instantiated per type). Examples are in `tests/cases/stdlib_*.csh`.

| Namespace | File | Contents |
|---|---|---|
| global | `core.csh` | `IDisposable`, `IComparable<T>`, `IEquatable<T>`, `IHashable`, `sqrt` |
| `System` | `list.csh`, `dictionary.csh`, `hashset.csh`, `stringbuilder.csh`, `process.csh`, `file.csh`, `directory.csh`, `encoding.csh` | `List<T>`, `Dictionary<K,V>`, `HashSet<T>`, `StringBuilder`, `Process`, `KeyValuePair<K,V>`, `File`, `Directory`, `Path`, `Encoding` (`using System;`) |
| `Char` | `char.csh` | `Char.IsDigit/IsLetter/IsLetterOrDigit/IsHexDigit/IsWhiteSpace/IsUpper/IsLower/ToUpper/ToLower/HexValue` |
| `System.Native` | `args.csh` | a helper function for `Main(string[] args)` |
| `Math` | `math.csh` | math functions and constants (without `using`: `Math.Sqrt(2)`) |
| `String` | `string.csh` | string helpers, visible as methods on `string` |
| `System.Native` | `native.csh` | C imports (`fopen`, `sin`, `pthread_mutex/cond_*`, …), also usable by your own programs (`using System.Native;`) |
| `System` | `thread.csh`, `mutex.csh` | `Thread`/`Thread<T>`, `SharedPtr<T>`, `Mutex<T>` (`using System;`, see [threading.md](language/threading.md)) |
| `System` | `random.csh` | `Random`: seeded pseudo-random numbers |

**`List<T>`** — a growable array. Create it with `List<int>.Create()` (or `new List<int>()`).
`Add`, `AddRange(T[])`, `Insert(i, v)`, `RemoveAt(i)`, `Remove(v)`, `Clear()`, `Get(i)` / `list[i]`, `Set(i, v)` /
`list[i] = v`, `Count()`, `Capacity()`, `IndexOf(v)`, `Contains(v)` (T: `IEquatable<T>`), `Sort()` (T:
`IComparable<T>`, stable), `Reverse()`, `ToArray()`; with functions: `ForEach(action)`, `Where(test)` (a new list),
`Select<U>(convert)`, `Any(test)`, `All(test)`, `FindIndex(test)` (`list.Where(x => x > 0)`). `foreach (var x in
list)` works. An invalid index ends the program with a panic.

**`Dictionary<TKey, TValue>`** — a hash table. `Create()`, `Set(k, v)` / `dict[k] = v`, `Get(k)` / `dict[k]` (panics
if the key is missing), `Add(k, v)` (`Error<void>`, fails on a duplicate key), `TryGet(k)` (`Optional<TValue>`), `GetOrDefault(k, fallback)`, `ContainsKey(k)`, `Remove(k)`,
`Clear()`, `Count()`, `Keys()`, `Values()`, `Entries()` (`KeyValuePair<K,V>[]`). Keys must satisfy `IEquatable` and
`IHashable`: numbers, `bool`, `char`, enums and `string` do so out of the box; your own structs define
`bool Equals(T other)` and `int GetHashCode()`.

> Since there are no classes, `List` and `Dictionary` are small structs that point at shared storage: copies
> (assignment, arguments) see the same elements. The storage is created by `Create()`, or by the first `Add`/`Set`; an
> empty list from `new List<T>()` isn't yet connected to its copies before the first element is added — start with
> `Create()` if you hand it out before adding to it.

**`StringBuilder`** — builds text without copying on every `+`: `var sb = StringBuilder.Create(); sb.Append("x"); sb.Append('c'); sb.AppendLine("…");
sb.Length(); sb.Get(i); sb.Clear(); string s = sb.ToString();` (a handle to shared storage, like `List`).
**`HashSet<T>`** — `Create()`, `Add(v)` (`true` if it was new), `Contains(v)`, `Remove(v)`, `Count()`, `Clear()`,
`ToArray()`.
**`Process.Run("command")`** runs a command line through the shell and returns its exit code; `RunCapture("command")`
also captures what it wrote to stdout (`Optional<string>`); `GetEnv("NAME")` reads an environment variable
(`Optional<string>`); `IsWindows()` reports the platform.
**`Directory`** — `Exists(path)`, `Create(path)` (including parent directories), `GetEntries(path)` (names, sorted),
`FindFiles(path, extension)` (recursive, sorted), `GetCurrentDirectory()` (C library calls, no shell).
**`Path`** — `Combine`, `Normalize`, `GetDirectory`, `GetFileName`, `GetExtension`, `GetStem`, `ChangeExtension`,
`IsRooted`, `GetFullPath` (absolute, without `.`/`..`), `GetRelativePath(from, to)`.
**Command line:** `int Main(string[] args)` receives the arguments without the program name. `Console.WriteError(Line)`
writes to stderr, `string.FromCStr(char*)` copies a C string (`unsafe`) into a `string`.

**`File`** (static, text is UTF-8 by default): `ReadAllText(path [, encoding])`, `ReadAllBytes(path)`,
`WriteAllText(path, text [, encoding])`, `WriteAllBytes(path, bytes)`, `Exists(path)`, `Delete(path)`,
`Copy(source, target [, overwrite])`. Reading returns
`Error<string>` or `Error<uint8[]>`, writing and deleting return `Error<void>`; a UTF-8 BOM is skipped when reading
text. Paths go to the C library unchanged (so, on Windows, no non-ASCII characters in the path).

```csharp
using System;

Error<string> Load(string path)
{
    var text = try File.ReadAllText(path);
    try File.WriteAllText(path + ".bak", text);
    return text.Trim();
}
```

**`Encoding`** — `Encoding.UTF8()` and `Encoding.ASCII()`: `GetBytes(string)`, `GetString(uint8[] [, start, count])`
(`Error<string>`: invalid UTF-8, or bytes above 127 for ASCII, are errors), `GetByteCount`, `Name()`. Strings are
always UTF-8 in memory; `GetBytes` with ASCII replaces other characters with `?`. More encodings can be added as a
new `EncodingKind`.

**`Math`** — constants `PI`, `E`, `Tau`; `Abs`/`Min`/`Max`/`Clamp` (int, int64, float, double), `Sign`; `Sqrt`,
`Cbrt`, `Pow`, `Exp`, `Log`, `Log2`, `Log10`, `Hypot`; `Sin`, `Cos`, `Tan`, `Asin`, `Acos`, `Atan`, `Atan2`, `Sinh`,
`Cosh`, `Tanh`, `DegreesToRadians`, `RadiansToDegrees`; `Floor`, `Ceiling`, `Truncate`, `Round` (rounds half to even,
like in C#), `Lerp`, `IsNaN`, `IsInfinity`. Integer arguments are widened to `double` (`Math.Sqrt(2)`).

**String helpers** (`s.Contains(x)` ≙ `String.Contains(s, x)`, static as `string.Join(sep, parts)`): `IsNullOrEmpty`,
`Contains`, `IndexOf` (also `IndexOf(char, start)`), `LastIndexOf`, `StartsWith`, `EndsWith`, `Trim`,
`TrimStart`/`TrimEnd` (white space, or a given character), `PadLeft`/`PadRight` (with spaces or a given character),
`ToUpper`/`ToLower` (ASCII only), `Replace`,
`Repeat`, `Split` (by character or string), `Join`, `ParseInt`/`ParseInt64`/`ParseDouble` (`Error<…>`), plus
`Equals`, `GetHashCode` (FNV-1a) and `CompareTo` (byte-wise). Positions are byte offsets;
`string.FromBytes(bytes [, start, count])` builds a string from bytes. New helpers are just written as a function in
`namespace String` (the first parameter is the string).

**`Thread`/`Thread<T>`** — the handle returned by `start`ing a `thread` function (`start Foo(args)`; calling one
directly, without `start`, is a compile-time error): `Join()`, `Cancel()`, `CancelAndWait()`, `IsCompleted()`,
`IsCancelled()`, and (`Thread<T>` only) the non-blocking `t is T value` pattern. Real OS threads (pthreads on
every supported platform), isolated from global state; parameters are values, strings (copied for the thread) and
`SharedPtr<T>`/`Mutex<T>` of thread-safe values — see [threading.md](language/threading.md), including
`Thread.Cancelled`.
**`SharedPtr<T>`** — `Create(value)`, `Get()`, `Ptr()` (`unsafe`), `IsNull()`: a box with an atomically
reference-counted handle, safe to share between threads (unlike strings/arrays/containers).
**`Mutex<T>`** — `Create(value)`, `Lock()` (a `MutexGuard<T>` with `Get()`/`Set(v)`, released by `Dispose()`/`using`),
`Get()`, `Set(v)`, `Update(change)` (`counter.Update(n => n + 1)`): a value shared by threads under a lock; values go
in and out as copies (see [threading.md](language/threading.md)).

**`Random`** — `Random.Create(seed)` (the same sequence for the same seed, on every system) or `Random.Create()`
(seeded from the clock): `Next()`, `Next(max)`, `Next(min, max)`, `NextDouble()` (`[0, 1)`), `NextBool()`,
`NextBits()`. xorshift64*, not for cryptography. A `Random` is a value: keep it in a variable and call its methods
on that.

**Built into the compiler** (no library code): `Console.Write/WriteLine/WriteError/WriteErrorLine`,
`Memory.Allocate/Free` (`unsafe`), `Memory.CopyForThread(v)` (a copy that shares no reference count: strings get new
blocks), `Environment.Exit/Panic`, `Array.Copy`, `string.FromBytes`, `string.FromCStr` (`unsafe`), `ToString()`,
`CompareTo()`, `Equals()`, `GetHashCode()` on numbers, `int.MaxValue/MinValue`, `EmbedText`/`EmbedNames`/`EmbedTexts`
(files embedded at compile time).

**Writing library code:** the standard library is also the prelude that the frozen C++ compiler (stage 0) compiles
while it builds the self-hosted compiler. Code in `stdlib/` therefore uses only the language that compiler knows
(no lambdas, no string interpolation, no `x[i]` on lists); generic bodies are the exception, because they are only
compiled when they are used (`Mutex<T>` relies on this). See [compiler.md](compiler.md).

