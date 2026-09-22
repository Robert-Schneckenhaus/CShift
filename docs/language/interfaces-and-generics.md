← [Language guide](README.md)

# Interfaces and generics

## Interfaces

An interface lists methods only — no fields, no properties:

```csharp
interface IDisposable
{
    void Dispose();
}

interface IShape
{
    float Area();
}

struct Circle : IShape
{
    float Radius;

    float Area()
    {
        return Math.PI * Radius * Radius;
    }
}
```

A struct can implement several interfaces (in the base list, after its base struct if it has one); the compiler
checks that every method is actually implemented, with a matching signature.

Interfaces currently work as a **constraint** (below) and in base lists, but not yet as a variable or parameter type
of their own (that would need dynamic dispatch through a fat pointer). To process different shapes uniformly today,
use generics with a constraint, or a `switch`/`is` over a known set of structs.

## Generic structs and functions

```csharp
struct Pair<T>
{
    T First;
    T Second;
}

T Max<T>(T a, T b)
{
    return a > b ? a : b;
}

var p = Pair<int> { First = 1, Second = 2 };
int m = Max(3, 7);          // type argument inferred
int m2 = Max<int>(3, 7);    // or written out explicitly
```

The compiler monomorphizes: a native specialization is generated for every type combination that's actually used
(`Max<int>`, `Max<double>`, …). There's no generic mechanism at run time and no boxing.

## Constraints

```csharp
T Max<T>(T a, T b) where T : IComparable<T>
{
    return a.CompareTo(b) > 0 ? a : b;
}
```

The compiler checks, at compile time, that every type used for `T` actually implements the required interfaces.
Numbers and `string` already implement `IComparable<T>`/`IEquatable<T>`/`IHashable` out of the box; your own structs
implement them by defining the matching methods (`int CompareTo(T other)`, `bool Equals(T other)`,
`int GetHashCode()`).

```csharp
struct Money : IComparable<Money>
{
    int64 Cents;

    int CompareTo(Money other)
    {
        return Cents < other.Cents ? -1 : (Cents > other.Cents ? 1 : 0);
    }
}
```

This is exactly what `Dictionary<TKey, TValue>` needs from its key type (`IEquatable` + `IHashable`) and what
`List<T>.Sort()` needs from its element type (`IComparable<T>`) — see
[arrays, strings and collections](arrays-strings-collections.md).

Next: [Enums](enums.md).
