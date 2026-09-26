← [Language guide](README.md)

# Functions and function pointers

## Free functions and overloading

Functions can be defined in any file and called before their definition; no `static` keyword is needed:

```csharp
void Print(int value) { Console.WriteLine(value.ToString()); }
void Print(string value) { Console.WriteLine(value); }
void Print(float value) { Console.WriteLine(value.ToString()); }

Print(42);       // picks the int overload
Print("hi");     // picks the string overload
```

The compiler picks the best match from the argument types, the same way as C# overload resolution.

## Parameters

See [memory model](memory-model.md) for the full picture; in short, every parameter is one of:

```csharp
void ByValue(Vec2 v) { }              // a copy
void ByRef(ref Vec2 v) { v.X += 1; }  // a mutable alias
void ByConstRef(const ref Vec2 v) { } // a read-only alias, no copy
```

There is no `out` parameter — a function that needs to report success/failure or an optional result returns
`Error<T>` or `Optional<T>` instead (see [error handling](error-handling.md)).

## Function pointers: `Action` and `Func`

`Action<...>` (no result) and `Func<..., R>` (the last type argument is the result) are built-in types, up to 8
parameters, holding a function (or a lambda, below):

```csharp
int Square(int x) { return x * x; }
int Twice(int x) { return x * 2; }

Func<int, int> f = Square;
Console.WriteLine(f(5).ToString());   // 25

f = Twice;
Console.WriteLine(f(5).ToString());   // 10
```

You can assign the name of a free function or a `static` method; the signature has to match exactly (overloaded or
generic names are disambiguated by the target type, e.g. `Func<int, int> id = Identity<int>;`). Calling works as
`f(x)`, through a field (`obj.Callback(x)`), through an array element (`table[i](x)`), or with `.Invoke(x)`.

```csharp
void Repeat(Action action, int times)
{
    for (var i = 0; i < times; i += 1)
        action();
}

void Bump() { Console.WriteLine("bump"); }

Repeat(Bump, 3);
```

`null` is allowed for a function-pointer value; calling `null` panics. Function pointers are ordinary values — they
can live in fields, arrays, and be passed around or returned like any other value — and they compare with
`==`/`!=`. They're also C-compatible: a CShift function passed to a C callback parameter can be called by C
directly, and a function pointer C hands back can be called directly too (see [C interop](ffi-and-interop.md)).

## Lambdas and closures

A lambda is a function written where it is used. It has no type of its own: it takes the parameter and result types
from the `Action`/`Func` type it is converted to (written parameter types must match):

```csharp
Func<int, int> square = x => x * x;
Func<int, int, int> max = (a, b) => { if (a > b) return a; return b; };
Action hello = () => Console.WriteLine("hello");
Func<string, int> length = (string s) => s.Length;

list.ForEach(item => Console.WriteLine(item));
```

A lambda can use the variables of the enclosing function — it **captures a copy** of each one when it is created
(like C++'s `[=]`), so it can outlive the function, and the copies are **read-only** inside the lambda:

```csharp
Func<int, int> MakeAdder(int n)
{
    return x => x + n;        // 'n' is copied into the closure
}

var add5 = MakeAdder(5);
Console.WriteLine(add5(1));   // 6

int count = 0;
Action bump = () => { count = count + 1; };   // error: a lambda gets a read-only copy of 'count'
```

In a method, a lambda can use the fields and methods of the struct; it works on a copy of the struct taken when the
lambda is created. Captured values are released with the last copy of the function value (closures are reference
counted like strings).

* `var f = x => x + 1;` is an error — a lambda needs its `Action`/`Func` type.
* A lambda that captures nothing is a plain function and can be passed to C; passing one that captures variables
  to C panics.
* Lambdas cannot be passed to `thread` functions (`Action`/`Func` are not thread-transferable); a thread can create
  its own. A lambda in a `thread` function may not use global variables either.
* For generic functions, a lambda argument does not help to infer the type arguments: write them
  (`Map<string>(x => x.ToString())`).

Next: [Arrays, strings and collections](arrays-strings-collections.md).
