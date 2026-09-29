// cshiftc query: namespace names and calls through fields with a function type.
// query: 17 16 => "hover": "namespace Math"
// query: 17 21 => "hover": "const float64 PI = 3.141592653589793"
// query: 18 21 => "hover": "float64 Math.Sqrt(float64 x)"
// query: 20 17 => "hover": "int32 Ops.Twice(int32) (function field)"
// query: 20 17 => "line": 11
using System;

struct Ops
{
    Func<int, int> Twice;
}

int Main()
{
    var ops = Ops { Twice = x => x * 2 };
    double a = Math.PI * 2.0;
    double b = Math.Sqrt(a);
    Console.WriteLine(b.ToString());
    int c = ops.Twice(21);
    return c - 42;
}
