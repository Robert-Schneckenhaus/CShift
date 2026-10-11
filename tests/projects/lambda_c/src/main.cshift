// A lambda that captures nothing is a plain function, so C can call it.
using System;
using Native from "../native/apply.h";

int Main()
{
    Console.WriteLine(Native.apply_twice(x => x * 3, 2));
    Func<int, int> inc = x => x + 1;
    Console.WriteLine(Native.apply_twice(inc, 5));
    return 0;
}
