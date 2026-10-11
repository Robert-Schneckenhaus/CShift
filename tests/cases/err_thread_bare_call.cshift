// A 'thread' function can only be called through 'start'.
// expect-error: must be prefixed with 'start'

using System;

thread int Square(int x)
{
    return x * x;
}

void Main()
{
    Thread<int> t = Square(6);
}
