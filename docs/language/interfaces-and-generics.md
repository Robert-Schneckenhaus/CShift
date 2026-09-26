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

### Interface values

An interface is also a type of its own: a variable, parameter, field or list element of an interface type holds any
struct that implements it, and its methods are called through a method table (dynamic dispatch):

```csharp
IShape a = Circle { R = 1.0 };
IShape b = Rect { W = 2.0, H = 3.0 };

var shapes = List<IShape>.Create();
shapes.Add(a);
shapes.Add(b);
foreach (var s in shapes)
    Console.WriteLine(s.Area());

if (b is Rect r)                  // the struct again (a copy), if it is one
    Console.WriteLine(r.W);
```

* Converting a struct to an interface **copies it into a box**. Copies of the interface value share that box (like a
  boxed struct in C#), so a method that changes the struct is seen through every copy; the struct you started from
  is not affected. The box is reference counted and freed with the last copy.
* An interface value can be `null`; calling a method of a null interface value panics.
* An interface value satisfies a constraint on its own interface (`Biggest<IShape>(a, b)` with
  `where T : IShape`).
* Generics with a constraint stay the zero-cost option (no box, calls are direct); interface values are for
  collections of different structs and similar cases.

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
