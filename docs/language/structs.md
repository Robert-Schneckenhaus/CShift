← [Language guide](README.md)

# Structs

Structs are CShift's only user-defined data type — there are no classes. They are value types: assigning or passing
one copies it in full.

```csharp
struct Vec2
{
    float X;
    float Y;
}

var a = Vec2 { X = 10, Y = 20 };
var b = a;        // a full copy
b.X = 99;         // does not change a.X
```

## Field visibility

There's no `public`/`private` keyword. A field (or method) whose name starts with `_` is private; everything else is
public:

```csharp
struct Player
{
    int Health;           // public
    int _internalState;   // private
}
```

## Initializers

```csharp
var p1 = new Player();                 // every field gets its zero value (0, false, null, ...)
var p2 = Player { Health = 100 };      // an initializer sets the fields it names
```

There are no constructors. More elaborate setup is an ordinary function that returns the struct:

```csharp
Player CreatePlayer(int health)
{
    return Player { Health = health };
}
```

## Methods

```csharp
struct Vec2
{
    float X;
    float Y;

    float Length()
    {
        return sqrt(X * X + Y * Y);
    }

    static Vec2 Zero()
    {
        return Vec2 { X = 0, Y = 0 };
    }
}

var v = Vec2 { X = 3, Y = 4 };
Console.WriteLine(v.Length());     // 5
var origin = Vec2.Zero();
```

A method called on a `const ref` parameter (see [memory model](memory-model.md)) runs on a copy, so the read-only
guarantee always holds.

## Nested structs

```csharp
struct Rect
{
    Vec2 Position;
    Vec2 Size;
}

var r = Rect { Position = Vec2 { X = 0, Y = 0 }, Size = Vec2 { X = 100, Y = 50 } };
```

A struct can't contain itself (directly or through a cycle of structs) — use an array/`List<T>` of handles for
recursive data.

## Inheritance

A struct can have exactly one base struct, listed first, plus any number of interfaces:

```csharp
struct Animal
{
    int Age;
}

struct Dog : Animal
{
    string Name;
}

Dog d = Dog { Age = 2, Name = "Rex" };   // fields of the base struct are set the same way
Animal a = d;                             // upcast: an ordinary copy of the Animal part
```

There's no multiple inheritance of structs, and no hidden object hierarchy — inheritance is just part of the memory
layout (the base struct's fields come first). A method in a derived struct with the same name and signature as one
in the base hides it.

Next: [Interfaces and generics](interfaces-and-generics.md).
