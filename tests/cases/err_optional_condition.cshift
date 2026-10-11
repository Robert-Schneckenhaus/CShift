// Optional<T> is not a condition: 'x is T v' or 'x != null' say what is tested.
// expect-error: 'Optional<int32>' cannot be used as a condition; test it with 'is int32 v' (has a value) or '== null' / '!= null'

using System;

Optional<int> Find(int key)
{
    if (key < 0)
        return null;
    return key;
}

int Main()
{
    var o = Find(1);
    return o && true ? 0 : 1;
}
