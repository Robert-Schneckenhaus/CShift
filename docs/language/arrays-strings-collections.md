← [Language guide](README.md)

# Arrays, strings and collections

## Arrays

Arrays are managed dynamic data (see [memory model](memory-model.md)): reference semantics, ARC, a fixed length
after creation.

```csharp
var a = new int[10];
var b = new int[] { 1, 2, 3 };      // an initializer list
var jagged = new int[3][];           // an array of arrays

a[0] = 42;
Console.WriteLine(a.Length.ToString());

var c = a;          // c references the same array as a
var copy = a.Clone(); // an independent copy

Array.Copy(source, sourceIndex, destination, destinationIndex, count);
```

Indexing is bounds-checked; an out-of-range index panics.

### Collection expressions

`[a, b, c]` lists the elements; it becomes the type it is used as:

```csharp
int[] a = [1, 2, 3];                   // an array of exactly this length
Slice<int> s = [4, 5];                 // a new array, as a view
ReadOnlySlice<int> r = [6, 7];         // the same, read-only (in a constant: static data, no array)
List<string> names = ["ann", "bob"];   // Create(), then Add per element
HashSet<int> seen = [1, 2, 2];         // any struct with 'static Create()' and 'Add(T)'
int[] all = [..a, ..s, 6];             // ..x spreads an array, a slice or a collection with ToArray()
int[] none = [];
var inferred = [1.5, 2.0];             // no type to become: an array of the first element's type (double[])
Process([1, 2, 3]);                    // as an argument, the parameter's type decides
Optional<int[]> Find() { return [1, 2]; }   // Optional<T> / Error<T>: the T is built, then wrapped
```

An array or slice is built with one allocation of exactly the right length (spreads included). The elements convert
to the element type like in an assignment. `new int[n]` (a zeroed array of a given length) and
`new int[] { 1, 2, 3 }` still work.

### Fixed-size arrays: `Fixed<T, N>`

`int[]` is always a heap array. For small buffers of a known size there is `Fixed<T, N>`: N elements stored
**inline** - in the variable (on the stack) or inside the struct that has the field. No allocation, no reference
count:

```csharp
Fixed<int, 16> buffer;                        // 16 zeros
buffer[3] = 7;
buffer[^1] = 9;                               // ^n counts from the end
Fixed<float, 16> matrix = [1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1];

struct Vertex
{
    Fixed<float, 3> Pos;                      // 12 bytes inside the struct
}

const int Slots = 4;
Fixed<string, Slots> names = ["a", "b", "c", "d"];   // the size can be an integer constant
```

* **A value, like a struct:** assigning, passing and returning copy all elements, so nothing can refer to a Fixed
  after it is gone. Pass big ones as `ref` / `const ref` to avoid the copy.
* **Never mixed up with heap arrays:** there is no implicit conversion in either direction. `f.ToArray()` copies into a
  new `T[]`; `Fixed<int, 4> f = [..heapArray];` copies in (the length is checked when the program runs).
* **Checked:** a collection expression must have exactly N elements; a constant index outside `0..N-1` is a compile
  error, any other index is checked when the program runs.
* `Length` is a constant, `foreach` works, and so do `Fixed` of structs, `Fixed` of `Fixed`, `Fixed` in lists,
  `Optional<Fixed<T, N>>` and generic parameters (`T First<T>(Fixed<T, 2> pair)`).
* A `Fixed` of plain values can be a `thread` parameter (it is copied like any value).
* C arrays in structs (`float m[16]`, `int grid[2][3]`) are imported as `Fixed<float32, 16>` and
  `Fixed<Fixed<int32, 3>, 2>` ([C interop](ffi-and-interop.md)).

## Strings

Strings are UTF-8, immutable, and managed by ARC. Modifying one produces a new string:

```csharp
string name = "Ann";
string greeting = "Hello, " + name + "!";
char first = greeting[0];
int len = greeting.Length;
string part = greeting.Substring(7, 3);

if (greeting == "Hello, Ann!")
    Console.WriteLine("match");
```

Building text piece by piece is cheap: `text += ...` (and `text = text + a + b`) on a local variable appends in place
when nothing else refers to the string - no copy, a loop of appends takes linear time. A string that is shared (a
copy in another variable, a slice of it, a parameter that the caller still holds) is never changed: it is copied
first, exactly as immutability requires. The same holds for the pieces of `a + b + c`.

```csharp
string log = "";
foreach (var item in items)
    log += item.Name + ": " + item.Count.ToString() + "\n";   // linear, like a StringBuilder
```

**Interpolated strings** put values into text; `{x}` is the same as `+ x +`, so anything that can be added to a
string works (numbers, `bool`, `char`, strings, and structs with a `string ToString()` method). `{{` and `}}` are
braces:

```csharp
int count = 3;
string text = $"{name} has {count} item(s), {count * 2} in total {{approx.}}";
const string Title = $"{AppName} {Version}";   // works in constants too
```

Numbers become the shortest text that reads back as the same value: `0.1`, `1.0 / 3.0` is `0.3333333333333333`.

### Number formats and alignment

`ToString("F2")` and `{x:F2}` in an interpolated string format a number; `{x,8}` fills the text with spaces on the
left up to 8 characters, `{x,-8}` on the right (for any value), and both combine as `{x,8:F2}`:

```csharp
double price = 1234.5;
Console.WriteLine($"{"Total",-8}|{price,12:N2}|");   // "Total   |    1,234.50|"
string hex = 255.ToString("X4");                     // "00FF"
```

| Format | For | Result |
|---|---|---|
| `D5` | integers | at least 5 digits: `42` → `00042` |
| `X`, `x4` | integers | hexadecimal, upper/lower case, at least 4 digits: `255` → `FF`, `00ff`; negative values in two's complement of the type's size |
| `B8` | integers | binary, at least 8 digits: `5` → `00000101` |
| `F2` | all numbers | fixed point with 2 decimals (default 2): `3.14159` → `3.14` |
| `N2` | all numbers | like `F`, with `,` between thousands: `1234567` → `1,234,567.00` |
| `E3`, `e3` | all numbers | scientific, 3 decimals (default 6): `1234.5` → `1.235E+003` |
| `P1` | all numbers | percent (times 100), 1 decimal (default 2): `0.256` → `25.6 %` |
| `G` | all numbers | the same as `ToString()` |

* The letter can be followed by up to two digits (0 to 99). The text is the same on every platform: `.` for the
  decimal point and `,` between thousands, no locale.
* Floating point values are formatted from their exact binary value and rounded half away from zero, like .NET:
  `0.125.ToString("F2")` is `0.13`, `2.5.ToString("F0")` is `3`. A result that is zero has no minus sign
  (`(-0.001).ToString("F2")` is `0.00`).
* A format written as a string literal is checked by the compiler; a format that is only known at run time panics
  if it is invalid.
* In a hole, the `:` of a conditional `a ? b : c` is part of the expression, the next `:` starts the format.
* The alignment counts bytes (like `PadLeft`), so text with non-ASCII characters lines up only in bytes.
* A hole with a format or alignment is not a constant expression (it calls the standard library).

More string operations are extension-style methods from the standard library (`Contains`, `Trim`, `Split`, `Join`,
`PadLeft`, `ParseInt`, …) — see the [standard library](../stdlib.md) for the full list.

## Slices

`a[i..j]` is a **view** of the elements `i` to `j - 1` of an array, a string or another slice — nothing is copied:

```csharp
int[] a = new int[] { 1, 2, 3, 4, 5 };
Slice<int> mid = a[1..4];        // 2, 3, 4
var head = a[..2];               // 1, 2
var tail = a[3..];               // 4, 5
var last = a[^2..];              // ^n counts from the end: 4, 5
int end = a[^1];                 // also for a single element: 5

string s = "hello world";
StringSlice word = s[6..];       // "world"
bool same = word == "world";     // slices and strings compare by their bytes
```

* An array gives a `Slice<T>`, a string a `StringSlice` (byte offsets, like `s[i]`). Slices have `Length`, `[i]`
  (also `[^i]`), `foreach`, slicing again, and `==` for string slices; they go into text like strings (`"x" + word`,
  `word + other`, `$"{word}"`). A `StringSlice` has the methods of strings (`Trim`, `Split`, `IndexOf`, ...) and can be
  a key of a `Dictionary` or sorted in a `List` like a string.
* A slice is a small value (the array or string it belongs to, the first element and the length). It holds a
  reference to that block, so it can be stored, returned and put into lists like any value; it also keeps the
  **whole** block alive (`bigText[0..10]` keeps all of `bigText`). Copy out with `word.ToString()` or
  `mid.ToArray()` — copying is always explicit; a slice never turns into a `string` or array by itself.
* A `Slice<T>` writes through: `mid[0] = 20` changes `a[1]` (arrays are shared anyway). A `StringSlice` is read-only.
* `ReadOnlySlice<T>` is the same view without write access: `view[0] = 1` is a compile error. Arrays, `Slice<T>` and
  collection expressions convert to it for free (never the other way), so `int Sum(ReadOnlySlice<int> values)` accepts
  all of them and promises not to change them. Slicing a `ReadOnlySlice<T>` gives another one; `ToArray()` copies it
  into a normal array. [Constant slices](constants-and-globals.md#constant-slices) have this type.
* A whole string or array converts to a slice for free, so a function that takes `StringSlice` or `Slice<T>` accepts
  both: `int Sum(Slice<int> values)` can be called with `a` or `a[1..]`.
* Text is also a `ReadOnlySlice<char>`: a `string` or `StringSlice` converts to it for free, so code written for
  slices of characters takes text too (a `string` argument prefers a `StringSlice` parameter). `text.AsBytes()` is the
  same view as `ReadOnlySlice<uint8>`, for functions that take bytes: `stream.Write(line.AsBytes())`.
* Ranges are checked: `0 <= start <= end <= Length`, otherwise the program panics like with an index out of range.
* A `ReadOnlySlice<T>` can be passed to a `thread` function: the thread gets its own copy of the elements
  ([threading.md](threading.md#isolation)). `Slice<T>` and `StringSlice` cannot (the block's reference count is
  not atomic, and a `Slice<T>` could be written); pass `word.ToString()` for a `StringSlice`. In `unsafe` code, `.Ptr()` gives a pointer to the first element (no terminating NUL);
  `word.CStr()` gives the text followed by a 0 byte for C (a copy only if the slice does not reach the end of its string).

## `List<T>`

A growable array:

```csharp
using System;

var names = List<string>.Create();
names.Add("Ann");
names.Add("Bob");
names.Insert(0, "Zoe");

foreach (var name in names)
    Console.WriteLine(name);

Console.WriteLine(names.Count().ToString());
names.Sort();       // needs T : IComparable<T>

names[0] = "Amy";   // the indexer: names.Set(0, "Amy")
string first = names[0];
var longNames = names.Where(n => n.Length > 3);
```

**Indexers:** `x[k]` calls `x.Get(k)` and `x[k] = v` calls `x.Set(k, v)` (also `x[k] += v`), for `List<T>`,
`Dictionary<K, V>` and any struct of your own with such methods.

## `Dictionary<TKey, TValue>`

A hash table; keys need `IEquatable`/`IHashable` (numbers, `bool`, `char`, enums and `string` already have them —
see [interfaces and generics](interfaces-and-generics.md) for adding them to your own structs):

```csharp
var ages = Dictionary<string, int>.Create();
ages["Ann"] = 30;                       // ages.Set("Ann", 30)
ages["Ann"] += 1;
int annsAge = ages["Ann"];              // panics if the key is missing

if (ages.TryGet("Ann") is int age)
    Console.WriteLine(age.ToString());

foreach (var entry in ages.Entries())
    Console.WriteLine(entry.Key + ": " + entry.Value.ToString());
```

> `List` and `Dictionary` are small structs pointing at shared storage (there are no classes), so a copy sees the
> same elements as the original. Start one with `.Create()` if you're going to hand out copies of it before adding
> anything — an empty `new List<T>()` isn't connected to its copies yet.

## `HashSet<T>`, `Stack<T>`, `Queue<T>` and `StringBuilder`

```csharp
var seen = HashSet<int>.Create();
if (seen.Add(id))
    Console.WriteLine("new");

var undo = Stack<string>.Create();     // last in, first out
undo.Push("move");
string last = undo.Pop();              // panics when empty; TryPop() gives an Optional<string>

var jobs = Queue<Job>.Create();        // first in, first out
jobs.Enqueue(job);
while (jobs.TryDequeue() is Job next)
    Run(next);

var sb = StringBuilder.Create();
sb.Append("x = ");
sb.Append(42.ToString());
sb.AppendLine();
string text = sb.ToString();
```

Next: [Constants and global variables](constants-and-globals.md).
