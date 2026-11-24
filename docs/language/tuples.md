← [Language guide](README.md)

# Tuples

A tuple groups a few values without a struct of its own: a function can return two results, a list can hold pairs,
a dictionary can use two numbers as its key.

```csharp
using System;

(int, int) MinMax(int[] values)
{
    int lo = values[0];
    int hi = values[0];
    foreach (var v in values)
    {
        lo = v < lo ? v : lo;
        hi = v > hi ? v : hi;
    }
    return (lo, hi);
}

int Main()
{
    var (lo, hi) = MinMax([3, 1, 7]);
    Console.WriteLine($"{lo} to {hi}");        // 1 to 7
    return 0;
}
```

## Tuple types and values

`(int, string)` is a type and `(1, "one")` a value of it. A tuple has 2 to 7 values; its values are the fields
`Item1`, `Item2`, ...:

```csharp
(string, int) entry = ("ann", 31);
Console.WriteLine(entry.Item1);     // ann
entry.Item2 += 1;
Console.WriteLine(entry);           // (ann, 32)
```

Tuple types can be used wherever a type can be written: variables, parameters, return values, fields, arrays
(`(int, int)[]`), type arguments (`List<(string, int)>`), `Optional<(int, int)>`.

A tuple value takes the type it is used as: a declaration with a type, a parameter, a return value, a field. Its
values are converted to that type's values, so `(int64, uint8) wide = (1, 2);` works. Without such a type (`var`, a
generic parameter) the tuple has the types of its values, by the rules of `var`: `var t = (1, "a");` is an
`(int, string)`. A value without a type of its own (`null`) needs a target type: `(int, string) t = (1, null);`.

## Deconstruction

A deconstruction takes a tuple apart into variables:

```csharp
var (lo, hi) = MinMax(values);           // two new variables, their types from the tuple
(string name, int age) = entry;          // with explicit types
var (_, second) = entry;                 // '_' skips a value
```

Its parts may also be existing variables, fields or array elements. The tuple is computed completely before
anything is assigned, so swapping needs no helper variable:

```csharp
(a, b) = (b, a);
(point.X, point.Y) = (0, 0);
```

`foreach` takes every element apart:

```csharp
var ages = List<(string, int)>.Create();
ages.Add(("ann", 31));
foreach (var (name, age) in ages)
    Console.WriteLine($"{name}: {age}");
```

The value must be a tuple of exactly as many values as the deconstruction has parts; anything else is a compile
error.

## Tuples are values

A tuple is a struct of the standard library (`Tuple2<T1, T2>` to `Tuple7<...>` in
[stdlib/tuple.cshift](../../stdlib/tuple.cshift)), and behaves like every other struct: assigning or passing it copies
it, strings and arrays in it are counted by ARC, it is stored inline (in an array of tuples, in a field) and needs no
allocation of its own. Error messages name it the way it is written: `(int32, string)`.

Every tuple type has three methods, which can be used whenever the types of its values have them:

* `Equals(other)` compares the values one by one: `(1, "a").Equals((1, "a"))` is `true`. There is no `==` for
  tuples (as for other structs).
* `GetHashCode()` combines the hash codes of the values, so a tuple of numbers, strings and the like can be the key
  of a `Dictionary` or the value of a `HashSet`:

  ```csharp
  var grid = Dictionary<(int, int), string>.Create();
  grid[(2, 3)] = "tree";
  ```

* `ToString()` writes the values in parentheses, so `$"{t}"` prints `(1, a)`.

## Limits

* The values of a tuple have no names: `(int Count, string Name)` is not a type. Use `Item1`, `Item2`, deconstruct the
  tuple, or declare a struct when the meaning of the values matters.
* A tuple does not convert to a tuple of other types: `(int, int) a = ...; (int64, int64) b = a;` is an error (only a
  tuple value written as `(x, y)` takes the types of its target).
* At most 7 values; a nested tuple (`((1, 2), 3)`) is one way to go beyond, a struct the better one.
