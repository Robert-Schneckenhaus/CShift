// Only arrays, slices and collections with ToArray() can be spread.
// expect-error: '..' spreads an array, a slice or a collection with ToArray(), not 'int32'

using System;

int Main()
{
    int n = 3;
    int[] a = [1, ..n];
    return a.Length;
}
