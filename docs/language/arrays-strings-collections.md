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
```

An array or slice is built with one allocation of exactly the right length (spreads included). The elements convert
to the element type like in an assignment. `new int[n]` (a zeroed array of a given length) and
`new int[] { 1, 2, 3 }` still work.

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

**Interpolated strings** put values into text; `{x}` is the same as `+ x +`, so anything that can be added to a
string works (numbers, `bool`, `char`, strings, and structs with a `string ToString()` method). `{{` and `}}` are
braces:

```csharp
int count = 3;
string text = $"{name} has {count} item(s), {count * 2} in total {{approx.}}";
const string Title = $"{AppName} {Version}";   // works in constants too
```

Numbers become the shortest text that reads back as the same value: `0.1`, `1.0 / 3.0` is `0.3333333333333333`.

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
  `$"{word}"`).
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
* Ranges are checked: `0 <= start <= end <= Length`, otherwise the program panics like with an index out of range.
* No slice (`Slice<T>`, `ReadOnlySlice<T>`, `StringSlice`) can be passed to a `thread` function (its block's reference count is not atomic); pass
  `word.ToString()` instead. In `unsafe` code, `.Ptr()` gives a pointer to the first element (no terminating NUL).

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

## `HashSet<T>` and `StringBuilder`

```csharp
var seen = HashSet<int>.Create();
if (seen.Add(id))
    Console.WriteLine("new");

var sb = StringBuilder.Create();
sb.Append("x = ");
sb.Append(42.ToString());
sb.AppendLine();
string text = sb.ToString();
```

Next: [Constants and global variables](constants-and-globals.md).
