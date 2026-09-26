// Loops follow the same rule: 'foreach (...) if (...)' needs braces around the 'if'.
// expect-error: a nested 'if' needs braces: the body of 'foreach' must be a block '{ ... }' when it is a control statement

using System;

int Main()
{
    int[] values = new int[] { 1, 2, 3 };
    int sum = 0;
    foreach (var v in values)
        sum += v;
    foreach (var v in values)
        if (v == 2)
            return 1;
    return 0;
}
