// A 'thread' function cannot have a 'ref'/'const ref' parameter.
// expect-error: cannot be 'ref' or 'const ref'

using System;

thread void Bad(ref int x)
{
    x += 1;
}

void Main()
{
    int n = 1;
    Bad(ref n).Join();
}
