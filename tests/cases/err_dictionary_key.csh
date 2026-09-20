// Dictionary keys must implement IEquatable and IHashable.
// expect-error: does not satisfy the constraint
using System;

struct Plain
{
    int X;
}

int Main()
{
    var d = Dictionary<Plain, int>.Create();
    return 0;
}
