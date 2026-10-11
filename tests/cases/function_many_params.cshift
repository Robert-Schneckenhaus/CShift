// Function values with more than 8 parameters (up to 16, like C#): a function, a lambda that captures a variable, and
// a function value called through a struct field - C functions with many parameters (XPutImage has 10) can be called
// through a pointer the same way.
// expect-exit: 0
// expect-stdout: 55 901 16

using System;

int Sum10(int a, int b, int c, int d, int e, int f, int g, int h, int i, int j)
{
    return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * h + 9 * i + 10 * j;
}

int Count16(int a, int b, int c, int d, int e, int f, int g, int h, int i, int j, int k, int l, int m, int n, int o, int p)
{
    return a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p;
}

struct Table
{
    Func<int, int, int, int, int, int, int, int, int, int, int, int, int, int, int, int, int> Count;
}

int Main()
{
    Func<int, int, int, int, int, int, int, int, int, int, int> f = Sum10;
    int k = 100;
    Func<int, int, int, int, int, int, int, int, int, int> g = (a, b, c, d, e, x, y, h, i) => a + i * k;
    var table = Table { Count = Count16 };
    Console.WriteLine($"{f(1, 1, 1, 1, 1, 1, 1, 1, 1, 1)} {g(1, 2, 3, 4, 5, 6, 7, 8, 9)} {table.Count(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)}");
    return 0;
}
