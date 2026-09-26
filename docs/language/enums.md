← [Language guide](README.md)

# Enums

An enum always names an explicit integer base type, so its size and representation are deterministic:

```csharp
enum Color : uint8
{
    Red,      // 0
    Green,    // 1
    Blue      // 2
}
```

Members can have explicit values, including expressions made of earlier constants and members (the compiler
computes them at compile time — see [constants and globals](constants-and-globals.md)):

```csharp
enum Flags : uint8
{
    None  = 0,
    Read  = 1,
    Write = 2,
    Both  = Read | Write,     // 3
    Next  = 1 << 3             // 8
}
```

## Using enums

```csharp
Color c = Color.Green;

switch (c)
{
    case Color.Red:
        Console.WriteLine("red");
        break;
    default:
        Console.WriteLine("other");
        break;
}

int raw = (int)c;               // explicit cast to the underlying integer
Color back = (Color)1;          // and back
bool has = (flags & Flags.Write) == Flags.Write;
```

Enum values compare with `==`/`!=`/`<`/`>`/`<=`/`>=` and support the bitwise operators `& | ^ ~`, which is the usual
pattern for flag enums like `Flags` above.

As text - `"color " + c`, `$"{c}"`, `c.ToString()`, also in constants - an enum value is the name of its member
(`Green`), like in C#. A value that is no member prints its number (`(Color)9` → `9`); members that share a value
print the first name. `(int)c` gives the number.

Error codes are enums as well, declared with `error Name { ... }`: see [error enums](error-handling.md#error-enums-typed-error-codes).

Next: [Memory model](memory-model.md).
