// 'is not' can only bind a variable as the whole condition of an 'if'.
// expect-error: 'is not' can only bind 'v' as the whole condition of an 'if' (then 'v' is usable in the 'else' branch, and after the 'if' if its branch returns, breaks or continues)

using System;

Optional<int> Find(int key)
{
    if (key < 0)
        return null;
    return key;
}

int Main()
{
    while (Find(1) is not int v)
        return 1;
    return 0;
}
