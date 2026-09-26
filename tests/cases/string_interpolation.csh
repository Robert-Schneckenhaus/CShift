// Interpolated strings: $"...{expression}..." is string concatenation, so every value that can be added to a string
// can be used (numbers, bool, char, strings, structs with 'string ToString()'). "{{" and "}}" are braces. Works in
// constants as well.
// expect-exit: 0
// expect-stdout: a=3, d=0.5, s=x, sum=7, {braces}
// expect-stdout: nested [xx], cond big
// expect-stdout: Hi Ann, 3!
// expect-stdout: tab	true é c
// expect-stdout: p = P(5), list of 2
// expect-stdout: no holes

using System;

struct P
{
    int X;

    string ToString()
    {
        return $"P({X})";
    }
}

const string Name = "Ann";
const string Greeting = $"Hi {Name}, {1 + 2}!";

int Main()
{
    int a = 3;
    double d = 0.5;
    string s = "x";
    Console.WriteLine($"a={a}, d={d}, s={s}, sum={a + 4}, {{braces}}");
    Console.WriteLine($"nested {$"[{s}{s}]"}, cond {(a > 2 ? "big" : "small")}");
    Console.WriteLine(Greeting);
    Console.WriteLine($"tab\t{true} é {'c'}");
    var p = P { X = 5 };
    var list = List<int>.Create();
    list.Add(1);
    list.Add(2);
    Console.WriteLine($"p = {p}, list of {list.Count()}");
    Console.WriteLine($"no holes");
    return 0;
}
