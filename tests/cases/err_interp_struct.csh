// A struct can be used in an interpolated string only if it has 'string ToString()'.
// expect-error: cannot convert 'Point' to a string (give it a method 'string ToString()')

using System;

struct Point
{
    int X;
}

void Main()
{
    var p = Point { X = 1 };
    Console.WriteLine($"{p}");
}
