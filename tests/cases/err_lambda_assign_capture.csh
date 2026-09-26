// A lambda gets a read-only copy of the variables it uses.
// expect-error: cannot assign to 'count': a lambda gets a read-only copy of the variables it uses

using System;

int Main()
{
    int count = 0;
    Action increment = () => { count = count + 1; };
    increment();
    return count;
}
