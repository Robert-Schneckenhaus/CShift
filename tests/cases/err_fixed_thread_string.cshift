// A Fixed can be a thread parameter only if its elements can (plain values, not strings).
// expect-error: not 'Fixed<string, 2>' (parameter 'names')

using System;

thread int Count(Fixed<string, 2> names)
{
    return names.Length;
}

int Main()
{
    return 0;
}
