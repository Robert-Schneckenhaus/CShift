// Only arrays, strings and slices can be sliced.
// expect-error: cannot slice a value of type 'System.List<int32>' (only arrays, strings and slices)

using System;

int Main()
{
    var list = List<int>.Create();
    var part = list[1..];
    return 0;
}
