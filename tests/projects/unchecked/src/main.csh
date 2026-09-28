// "unchecked": true in cshift.json: integer overflow wraps around in the whole project.
using System;

int Main()
{
    int x = int.MaxValue;
    x += 1;
    Console.WriteLine(x.ToString());
    int64 big = int64.MaxValue;
    Console.WriteLine((big * 2).ToString());
    return 0;
}
