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
