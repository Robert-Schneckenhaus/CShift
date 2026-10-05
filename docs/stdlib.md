# Standard library

← [Documentation](README.md)

The standard library is written in CShift itself (`stdlib/*.csh`) and embedded in the compiler. Only what a program
actually uses gets compiled (generics are instantiated per type). Examples are in `tests/cases/stdlib_*.csh`.

| Namespace | File | Contents |
|---|---|---|
| global | `core.csh` | `IDisposable`, `IComparable<T>`, `IEquatable<T>`, `IHashable`, `sqrt` |
| `System` | `list.csh`, `dictionary.csh`, `hashset.csh`, `stack.csh`, `queue.csh`, `stringbuilder.csh`, `process.csh`, `file.csh`, `directory.csh`, `encoding.csh` | `List<T>`, `Dictionary<K,V>`, `HashSet<T>`, `Stack<T>`, `Queue<T>`, `StringBuilder`, `Process`, `KeyValuePair<K,V>`, `File`, `Directory`, `Path`, `Encoding` (`using System;`) |
| `Char` | `char.csh` | `Char.IsDigit/IsLetter/IsLetterOrDigit/IsHexDigit/IsWhiteSpace/IsUpper/IsLower/ToUpper/ToLower/HexValue` |
| `System.Native` | `args.csh` | a helper function for `Main(string[] args)` |
| `Math` | `math.csh` | math functions and constants (without `using`: `Math.Sqrt(2)`) |
| `FastTrig` | `fasttrig.csh` | table-based trigonometry with integer angles and fixed point results (`FastTrig.Sin(angle)`) |
| `String` | `string.csh` | string helpers, visible as methods on `string` |
| `System.Native` | `native.csh` | C imports (`fopen`, `sin`, `pthread_mutex/cond_*`, …), also usable by your own programs (`using System.Native;`) |
| `System` | `thread.csh`, `mutex.csh` | `Thread`/`Thread<T>`, `SharedPtr<T>`, `Mutex<T>` (`using System;`, see [threading.md](language/threading.md)) |
| `System` | `random.csh` | `Random`: seeded pseudo-random numbers |
| `System` | `datetime.csh` | `DateTime`, `TimeSpan`, `DayOfWeek`, `Stopwatch` |
| `System` | `stream.csh` | `FileStream`, `StreamReader`, `StreamWriter`, `SeekOrigin` |
| `System` | `json.csh` | `Json`, `JsonValue`, `JsonKind`, `JsonError` |
| `System` | `regex.csh` | `Regex`, `RegexMatch`, `RegexError` |
| `System` | `os/…`, `amiga/os.csh` | the operating system layer (`_Os`: clock, time zone, file times, seeking); the compiler adds the one of the target |
| `Amiga` | `amiga/hardware.csh` | `Hardware`: the Amiga's custom chips (take over the machine, copper, vertical blank, chip memory); only for `m68k-amigaos`, see [amiga.md](amiga.md#the-custom-chips-amigahardware) |
| `Amiga` | `amiga/graphics.csh` | `Screen`, `Bitmap`, `Sprite`, `CopperList`, `Blitter`, `SystemFont`: graphics with the blitter, sprites and the copper; only for `m68k-amigaos`, see [amiga.md](amiga.md#graphics-amigascreen-bitmap-the-blitter-and-sprites) |

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

**`StringBuilder`** — builds text without copying on every `+` (`Append` takes strings and string slices): `var sb = StringBuilder.Create(); sb.Append("x"); sb.Append('c'); sb.AppendLine("…");
sb.Length(); sb.Get(i); sb.Clear(); string s = sb.ToString();` (a handle to shared storage, like `List`).
**`HashSet<T>`** — `Create()`, `Add(v)` (`true` if it was new), `Contains(v)`, `Remove(v)`, `Count()`, `Clear()`,
`ToArray()`.
**`Stack<T>`** (last in, first out) — `Create()`, `Create(capacity)`, `Push(v)`, `Pop()`, `Peek()` (both panic when
empty), `TryPop()`, `TryPeek()` (`Optional<T>`), `Count()`, `Get(i)` (0 = top), `Contains(v)`, `Clear()`, `ToArray()`
(top first). `foreach` goes from the top down.
**`Queue<T>`** (first in, first out, a ring buffer) — `Create()`, `Create(capacity)`, `Enqueue(v)`, `Dequeue()`,
`Peek()` (both panic when empty), `TryDequeue()`, `TryPeek()` (`Optional<T>`), `Count()`, `Get(i)` (0 = front),
`Contains(v)`, `Clear()`, `ToArray()` (front first). `foreach` goes from the front to the back. Both are handles to
shared storage, like `List`.
**Number formats** (`numberformat.csh`) — `x.ToString("F2")`, `$"{x,8:F2}"`: `D`, `X`, `B`, `F`, `N`, `E`, `P`, `G`
with up to two digits, see [number formats](language/arrays-strings-collections.md#number-formats-and-alignment).
`NumberFormat.Check(format, floatingPoint)` tells why a format is not valid (`""` if it is).
**`Process.Run("command")`** runs a command line through the shell and returns its exit code; `RunCapture("command")`
also captures what it wrote to stdout (`Optional<string>`); `GetEnv("NAME")` reads an environment variable
(`Optional<string>`); `IsWindows()` reports the platform.
**`Directory`** — `Exists(path)`, `Create(path)` (including parent directories), `GetEntries(path)` (names, sorted),
`FindFiles(path, extension)` (recursive, sorted), `GetCurrentDirectory()` (C library calls, no shell),
`Delete(path [, recursive])` (an empty directory, or everything in it), `Move(source, target)` (`IoError<void>`).
**`Path`** — `Combine`, `Normalize`, `GetDirectory`, `GetFileName`, `GetExtension`, `GetStem`, `ChangeExtension`,
`IsRooted`, `GetFullPath` (absolute, without `.`/`..`), `GetRelativePath(from, to)`.
**Command line:** `int Main(string[] args)` receives the arguments without the program name. `Console.WriteError(Line)`
writes to stderr, `string.FromCStr(char*)` copies a C string (`unsafe`) into a `string`.

**`File`** (static, text is UTF-8 by default): `ReadAllText(path [, encoding])`, `ReadAllBytes(path)`,
`WriteAllText(path, text [, encoding])`, `WriteAllBytes(path, bytes)`, `Exists(path)`, `Delete(path)`,
`Copy(source, target [, overwrite])`, `Move(source, target [, overwrite])`, `GetLastWriteTime(path)` /
`GetLastWriteTimeUtc(path)` (`IoError<DateTime>`). Reading returns
`IoError<string>` or `IoError<uint8[]>`, writing, copying and deleting return `IoError<void>` (see *Error codes*
below); a UTF-8 BOM is skipped when reading text. Paths go to the C library unchanged (so, on Windows, no non-ASCII characters in the path).
Paths, names and commands (`File`, `Directory`, `Path`, the streams, `Process`) are `StringSlice` parameters: a string,
or a part of one such as `line.Trim()`, is passed without `.ToString()`; a part that does not reach the end of its
string is copied for the C library, a whole string is not.

```csharp
using System;

Error<string> Load(string path)
{
    var text = try File.ReadAllText(path);
    try File.WriteAllText(path + ".bak", text);
    return text.Trim();
}
```

**Error codes** ([error enums](language/error-handling.md#error-enums-typed-error-codes), `stdlib/errors.csh`):

| Enum | Members | Returned by |
|---|---|---|
| `IoError` | `CannotOpen` (1), `CannotWrite` (2), `CannotDelete` (3), `AlreadyExists` (4), `InvalidText` (5), `CannotCreate` (6), `CannotMove` (7) | `File.*`, `Directory.Delete/Move`, the streams |
| `ParseError` | `Invalid` (1), `OutOfRange` (2) | `ParseInt`, `ParseInt64`, `ParseDouble` |
| `EncodingError` | `OutOfBounds` (1), `NotAscii` (2), `InvalidUtf8` (3) | `Encoding.GetString` |

A caller can match a code (`case IoError.CannotOpen:`, `if (r is IoError code)`); a typed result converts to a
plain `Error<T>`, and `try` passes it on from a function returning `Error<T>` or the same typed result.

**`Encoding`** — `Encoding.UTF8()` and `Encoding.ASCII()`: `GetBytes(string)`, `GetString(uint8[] [, start, count])`
(`EncodingError<string>`: invalid UTF-8, or bytes above 127 for ASCII, are errors), `GetByteCount`, `Name()`. Strings are
always UTF-8 in memory; `GetBytes` with ASCII replaces other characters with `?`. More encodings can be added as a
new `EncodingKind`.

**`Math`** — constants `PI`, `E`, `Tau`; `Abs`/`Min`/`Max`/`Clamp` (int, int64, float, double), `Sign`; `Sqrt`,
`Cbrt`, `Pow`, `Exp`, `Log`, `Log2`, `Log10`, `Hypot`; `Sin`, `Cos`, `Tan`, `Asin`, `Acos`, `Atan`, `Atan2`, `Sinh`,
`Cosh`, `Tanh`, `DegreesToRadians`, `RadiansToDegrees`; `Floor`, `Ceiling`, `Truncate`, `Round` (rounds half to even,
like in C#), `Lerp`, `IsNaN`, `IsInfinity`. Integer arguments are widened to `double` (`Math.Sqrt(2)`).

**`FastTrig`** — trigonometry from tables, without floating point: fast on CPUs without an FPU (the 68000), for
raycasters, rotations and demo effects. Angles are `int`s with 1024 steps per full circle (`Quarter` = 256 = 90°); any
value works, it is taken modulo 1024 with a mask. `Sin`/`Cos` return `int16` in 1.14 fixed point (`SinOne` = 16384 =
1.0), so `(r * FastTrig.Cos(a)) >> 14` scales a length. `Tan`, `Cot`, `Sec` (1/cos) and `Csc` (1/sin) return 16.16
fixed point (`FixedOne` = 65536), 2147483647 or -2147483647 at their poles; `Sec`/`Csc` are the step lengths of a
raycaster's grid walk. `Atan2(y, x)` returns the angle of a vector (0..1023, within one step), `FromDegrees` /
`ToDegrees` convert (rounded). The tables (about 8 KB) are generated by `stdlib/tools/fasttrig.py`.

**String helpers** (`s.Contains(x)` ≙ `String.Contains(s, x)`, static as `string.Join(sep, parts)`) work on
[slices](language/arrays-strings-collections.md#slices): they take `StringSlice` (a `string` converts for free), can
be called on a string or a slice, and the ones that return a part of the text return a **view** (nothing is copied):

| Returns a view (`StringSlice`) | `Trim`, `TrimStart`/`TrimEnd` (white space, or a given character), `Substring` on a slice, `Split` (`StringSlice[]`, by character or string) |
|---|---|
| Queries | `IsNullOrEmpty`, `Contains`, `IndexOf` (also `IndexOf(char, start)`), `LastIndexOf`, `StartsWith`, `EndsWith` |
| New strings | `PadLeft`/`PadRight`, `ToUpper`/`ToLower` (ASCII only), `Replace`, `Repeat`, `Join` (of `string[]` or `StringSlice[]`) |
| Parsing | `ParseInt`/`ParseInt64`/`ParseDouble` (`ParseError<…>`) |

```csharp
string entry = "name = Ann Lee";
int eq = entry.IndexOf('=');
StringSlice key = entry[..eq].Trim();          // "name", a view of 'entry'
string value = entry[eq + 1..].Trim().ToString();   // keep a copy as a string
foreach (var part in "a, b, c".Split(','))     // StringSlice[]: no string per part
    Console.WriteLine(part.Trim());
```

`Equals`, `GetHashCode` (FNV-1a) and `CompareTo` (byte-wise) exist for strings and for `StringSlice` (the same hash
for the same text): both can be keys of a `Dictionary`, elements of a `HashSet` or sorted in a `List`. `+` joins slices
like strings, and `slice.CStr()` (`unsafe`) passes one to C. Positions
are byte offsets; `string.FromBytes(bytes [, start, count])` builds a string from bytes. New helpers are just written
as a function in `namespace String` (the first parameter is the `StringSlice`).

**`Thread`/`Thread<T>`** — the handle returned by `start`ing a `thread` function (`start Foo(args)`; calling one
directly, without `start`, is a compile-time error): `Join()`, `Cancel()`, `CancelAndWait()`, `IsCompleted()`,
`IsCancelled()`, and (`Thread<T>` only) the non-blocking `t is T value` pattern. Real OS threads (pthreads on
every supported platform), isolated from global state; parameters are values, strings and `ReadOnlySlice<T>` (copied for the thread) and
`SharedPtr<T>`/`Mutex<T>` of thread-safe values — see [threading.md](language/threading.md), including
`Thread.Cancelled`.
**`SharedPtr<T>`** — `Create(value)`, `Get()`, `Ptr()` (`unsafe`), `IsNull()`: a box with an atomically
reference-counted handle, safe to share between threads (unlike strings/arrays/containers).
**`Mutex<T>`** — `Create(value)`, `Lock()` (a `MutexGuard<T>` with `Get()`/`Set(v)`, released by `Dispose()`/`using`),
`Get()`, `Set(v)`, `Update(change)` (`counter.Update(n => n + 1)`): a value shared by threads under a lock; values go
in and out as copies (see [threading.md](language/threading.md)).

**`DateTime`** — a date and time of day (0001-01-01 to 9999-12-31, ticks of 100 ns), local or UTC (`IsUtc`):
`Now()`, `UtcNow()`, `Today()`, `Create(y, m, d [, h, min, s [, ms]])` (local), `CreateUtc(...)`,
`FromUnixSeconds/FromUnixMilliseconds` and `ToUnixSeconds/ToUnixMilliseconds`; `Year()`, `Month()`, `Day()`, `Hour()`,
`Minute()`, `Second()`, `Millisecond()`, `DayOfWeek()`, `DayOfYear()`, `Date()`, `TimeOfDay()`; `Add(TimeSpan)`,
`AddDays/AddHours/AddMinutes/AddSeconds/AddMilliseconds(double)`, `AddMonths/AddYears(int)` (Jan 31 + 1 month =
Feb 28/29), `Subtract(DateTime)` (a `TimeSpan`) and `Subtract(TimeSpan)`; `ToLocalTime()`, `ToUniversalTime()`;
`CompareTo`, `Equals` (also for `Sort()` and `Dictionary` keys); `IsLeapYear(year)`, `DaysInMonth(year, month)`.
`ToString()` is `2026-10-01 14:05:09`; `ToString(format)` knows `yyyy yy MMMM MMM MM M dddd ddd dd d HH H hh h mm m
ss s fff ff f tt` (English names), `'text'` and `\x` are copied; `ToIsoString()` gives ISO 8601 with the zone
(`…Z` or `…+02:00`). `DateTime.Parse(text)` (`ParseError<DateTime>`) reads `yyyy-MM-dd[(T| )HH:mm[:ss[.f…]]][Z|±hh:mm]`.
On AmigaOS the clock has no time zone (UTC = local) and a resolution of 1/50 s.
**`TimeSpan`** — a signed duration in ticks: `FromDays/FromHours/FromMinutes/FromSeconds/FromMilliseconds(double)`,
`FromTicks`, `Create(h, m, s)`, `Create(d, h, m, s [, ms])`; the parts `Days()` … `Milliseconds()`, the totals
`TotalDays()` … `TotalMilliseconds()`; `Add`, `Subtract`, `Negate`, `Duration` (absolute), `Multiply(factor)`;
`ToString()` is `[-][d.]hh:mm:ss[.fffffff]`.
**`Stopwatch`** — elapsed time from the monotonic clock: `StartNew()`, `Start()`, `Stop()`, `Reset()`, `Restart()`,
`IsRunning()`, `Elapsed()` (`TimeSpan`), `ElapsedMilliseconds()`, `ElapsedTicks()`. `Thread.Sleep(milliseconds)`
pauses the calling thread.

**`FileStream`** — a file read or written piece by piece: `OpenRead(path)`, `OpenReadWrite(path)`, `Create(path)`,
`Append(path)` (all `IoError<FileStream>`); `Read(buffer, offset, count)` (the number of bytes read, 0 at the end),
`ReadByte()` (-1 at the end), `Write(bytes)` (a `ReadOnlySlice<uint8>`: an array, a part of one, `text.AsBytes()`),
`Write(array, offset, count)`, `WriteByte(b)`, `WriteText(slice)` (UTF-8),
`Position()`, `Seek(offset, SeekOrigin.Begin/Current/End)`, `Length()`, `Flush()`, `Close()` / `Dispose()`.
**`StreamReader`** — `Open(path)`, `ReadLine()` (`Optional<string>`, without `\n` or `\r\n`; null at the end),
`ReadToEnd()`, `EndOfStream()`; a UTF-8 BOM is skipped, invalid bytes become `?`. **`StreamWriter`** — `Create(path)`,
`Append(path)`, `Write(text)`, `WriteLine([text])`, `Flush()`. All three are `IDisposable` (`using var r = try
StreamReader.Open(path);`); a stream is a value around the C library's `FILE`, so keep one owner (copies share it).

```csharp
using var reader = try StreamReader.Open("log.txt");
while (reader.ReadLine() is string line)
{
    if (line.StartsWith("ERROR"))
        Console.WriteLine(line);
}
```

**`Json`, `JsonValue`** — JSON text (RFC 8259): `Json.Parse(text)` (`JsonError<JsonValue>`; the message says the line
and column, `JsonError.TooDeep` above 512 nested arrays/objects); a `JsonValue` has a `Kind` (`JsonKind.Null`, `Bool`,
`Number`, `String`, `Array`, `Object`) and is made with `JsonValue.Null()`, `Bool(b)`, `Number(d)`, `String(s)`,
`NewArray()`, `NewObject()`. Reading: `IsNull()` … `IsObject()`, `AsBool()`, `AsNumber()`, `AsInt()`, `AsInt64()`,
`AsString()` (a panic for another kind), `Count()`; arrays: `v[i]` / `Get(i)`, `Set(i, x)`, `Add(x)`, `Items()`;
objects: `v["key"]` / `Get(key)` (JSON null if missing, so `doc["a"]["b"]` needs no checks), `Has(key)`, `Set(key, x)`,
`Remove(key)`, `Keys()` (in the order they were added). Writing: `ToString()` (compact), `ToIndentedString([spaces])`.
Numbers are doubles (written as integers when they are whole); copies of an array or object share its elements.

```csharp
var doc = try Json.Parse(try File.ReadAllText("config.json"));
int port = doc["server"]["port"].IsNumber() ? doc["server"]["port"].AsInt() : 8080;
var o = JsonValue.NewObject();
o.Set("port", JsonValue.Number(port));
Console.WriteLine(o.ToIndentedString());
```

**`Regex`** — regular expressions: `Regex.Create(pattern)` (`RegexError<Regex>`; the message says what is wrong and
where), `IsMatch(text)`, `Match(text [, start])` (`Optional<RegexMatch>`), `Matches(text)`, `Replace(text,
replacement)` (`$0`, `$1`…`$9`, `${n}`, `${name}`, `$$`), `Split(text)`. A **`RegexMatch`** has `Index`, `Length`,
`Value`, `Group(n)` / `Group(name)` (`""` if the group did not take part), `GroupMatched(n)`, `GroupIndex(n)`,
`GroupCount()`. Syntax: characters and escapes (`\.`, `\n`, `\xHH`, `\uHHHH`), `.`, sets `[a-z]` `[^...]`, `\d \w \s`
`\D \W \S`, `^ $` (lines with `(?m)`), `\A \z`, `\b \B`, groups `(...)`, `(?<name>...)`, `(?:...)`, `|`, `* + ? {n}
{n,} {n,m}` and their lazy forms (`*?`, ...), `(?i)` (ASCII letters) at the start. No backreferences or lookaround.
UTF-8 aware (`.` and sets match a whole character; positions are bytes). A search takes at most (pattern size) x
(text length) steps: the matcher remembers the states it tried, so patterns like `(a*)*b` cannot take exponential time.

```csharp
var date = try Regex.Create("(?<y>\\d{4})-(?<m>\\d{2})-(?<d>\\d{2})");
Console.WriteLine(date.Replace("due 2026-10-01", "${d}.${m}.${y}"));   // due 01.10.2026
```

**`Random`** — `Random.Create(seed)` (the same sequence for the same seed, on every system) or `Random.Create()`
(seeded from the clock): `Next()`, `Next(max)`, `Next(min, max)`, `NextDouble()` (`[0, 1)`), `NextBool()`,
`NextBits()`. xorshift64*, not for cryptography. A `Random` is a value: keep it in a variable and call its methods
on that.

**Built into the compiler** (no library code): `Console.Write/WriteLine/WriteError/WriteErrorLine`,
`Memory.Allocate/Free` (`unsafe`), `Memory.CopyForThread(v)` (a copy that shares no reference count: strings get new
blocks), `Environment.Exit/Panic`, `Array.Copy`, `string.FromBytes`, `string.FromCStr` (`unsafe`), `ToString()`,
`CompareTo()`, `Equals()`, `GetHashCode()` on numbers, `int.MaxValue/MinValue`. Files are embedded
at compile time with the keywords [`embed`/`embed_filenames`/`embed_lines`](language/constants-and-globals.md#embedded-files-embed-embed_filenames-and-embed_lines).

**Writing library code:** `stdlib/` is compiled by the compiler of the same commit, so it may use every language
feature; only the compiler's own sources are limited to the stage 0 release. See [compiler.md](compiler.md).

