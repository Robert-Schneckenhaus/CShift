// The body of 'else' may be another 'if' ('else if'), but not a loop without braces.
// expect-error: a nested 'while' needs braces: the body of 'else' must be a block '{ ... }' when it is a control statement

using System;

int Main()
{
    int n = 3;
    if (n < 0)
        return 1;
    else
        while (n > 0)
            n -= 1;
    return n;
}
