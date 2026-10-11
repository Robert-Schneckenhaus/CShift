// unsafe on a whole function or method, and before a single statement (whose declarations stay visible)
// expect-stdout: 42
// expect-stdout: 7
// expect-stdout: 5
// expect-stdout: 99
using System;

unsafe int ReadThrough(int* p)
{
    return *p;
}

struct Box
{
    int Value;

    unsafe int* Address() { return &Value; }

    static unsafe int Twice(int* p) { return *p * 2; }
}

int Main()
{
    int x = 42;
    unsafe int* p = &x;
    unsafe Console.WriteLine(*p);
    var b = Box { Value = 7 };
    unsafe Console.WriteLine(*b.Address());
    int five = 5;
    unsafe Console.WriteLine(ReadThrough(&five));
    int n = 0;
    unsafe n = Box.Twice(&x) + 15;
    Console.WriteLine(n);
    return 0;
}
