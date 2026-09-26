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

### Interface parameters (dynamic dispatch without allocation)

An interface can be the type of a `ref` or `const ref` parameter. The function then takes any struct that implements
the interface, and calls its methods through a method table — nothing is allocated:

```csharp
string Describe(const ref IShape shape)
{
    return $"{shape.Name()}: {shape.Area()}";
}

void Enlarge(ref IShape shape, double factor)
{
    shape.Grow(factor);
}

var c = Circle { R = 1.0 };
Console.WriteLine(Describe(c));       // const ref: the callee works on a copy on the caller's stack
Enlarge(ref c, 2.0);                  // ref: the callee changes c itself
```

* `const ref`: the caller passes a copy of its struct (on its stack, released after the call), so methods that change
  the struct cannot change the caller's value. Any value can be passed, also `Describe(Circle { R = 3.0 })`.
* `ref`: the caller passes its variable with `ref`, and the callee's changes are visible.
* `shape is Rect r` tells which struct it is (and copies it out); an interface parameter can be passed on to another
  function with an interface parameter.
* An interface is **not a value type**: no interface variables, fields, results, list elements, type arguments or
  lambda captures. That is what makes it free — the parameter can never outlive the struct it points to, so it
  needs no allocation and no reference count. For collections of different structs, use a
  [sum type](#sum-types) (inline, no allocation) or one list per struct type.
* Generics with a constraint (below) stay the zero-cost option when the struct type is known at compile time: calls
  are direct and can be inlined.

### Sum types

A `union` holds one value of several member types, stored inline together with a tag — no allocation. It is the way
to keep different structs in one variable, field or list:

```csharp
union Shape : IShape { Circle, Rect }

Shape s = Circle { R = 1.0 };            // a member converts to the union
var shapes = List<Shape>.Create();       // different shapes in one list, stored in place
shapes.Add(s);
shapes.Add(Rect { W = 2.0, H = 3.0 });

foreach (var shape in shapes)
    Console.WriteLine(shape.Area());     // IShape's methods are dispatched on the tag

if (s is Circle c) ...                   // the member again (a copy)

switch (s)
{
    case Circle c:
        ...
        break;
    case Rect r:
        ...
        break;
}
```

* The members can be any value types (`union Token { int, string, bool }`), each once. A union's size is the size of
  its largest member plus the tag.
* A union that lists interfaces (`: IShape`) requires every member to implement them, and can call their methods
  directly; a method that changes the member changes it inside the union. It also satisfies constraints on those
  interfaces (`where T : IShape`) and can be passed to `ref`/`const ref IShape` parameters.
* The default value of a union is empty: `is` never matches, and calling a method panics.
* A union can be passed to a `thread` function if all its members are thread-safe.

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
