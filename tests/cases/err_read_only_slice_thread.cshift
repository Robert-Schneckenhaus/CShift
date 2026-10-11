// A ReadOnlySlice can be passed to a thread only if its elements can be: not of arrays (their reference counts are not
// atomic, and the thread could change them).
// expect-error: not 'ReadOnlySlice<int32[]>' (parameter 'rows')

using System;

thread int Count(ReadOnlySlice<int[]> rows)
{
    return rows.Length;
}

int Main()
{
    int[][] a = [[1], [2]];
    var t = start Count(a);
    return t.Join();
}
