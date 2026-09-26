// A ReadOnlySlice cannot be passed to a thread either (its block's reference count is not atomic).
// expect-error: not 'ReadOnlySlice<int32>' (parameter 'values')

using System;

thread int Count(ReadOnlySlice<int> values)
{
    return values.Length;
}

int Main()
{
    int[] a = [1, 2];
    var t = start Count(a);
    return t.Join();
}
