// Errors in collection expressions, all in one run.
// expect-error: err_several_collections.csh:28:19: error: cannot implicitly convert 'string' to 'int32'
// expect-error: err_several_collections.csh:29:23: error: 'Fixed<int32, 3>' needs 3 elements, but the collection expression has 2
// expect-error: err_several_collections.csh:30:13: error: a collection expression cannot become 'Bag': it needs 'static Bag Create()' and 'Add(T)'
// expect-error: err_several_collections.csh:31:13: error: a collection expression cannot become 'int32' (only arrays, Slice<T>, ReadOnlySlice<T>, Fixed<T, N> and structs with Create() and Add())
// expect-error: err_several_collections.csh:32:13: error: cannot infer the type of '[]' here; give it a type (e.g. int[] a = [];)
// expect-error: err_several_collections.csh:33:19: error: '..' spreads an array, a slice or a collection with ToArray(), not 'bool'
// expect-error: err_several_collections.csh:34:21: error: cannot spread 'int32[]' into a collection of 'string'
// expect-error: err_several_collections.csh:35:15: error: cannot implicitly convert 'float64' to 'int32' (an explicit cast is required)
// expect-error: err_several_collections.csh:36:28: error: no matching function for call 'Add(int32)': argument 1: cannot convert 'int32' to 'string'
// expect-error: err_several_collections.csh:37:29: error: cannot implicitly convert 'string' to 'int32'
// expect-error: err_several_collections.csh:38:20: error: type 'int32[]' has no member 'Lenght'
// expect-error: err_several_collections.csh:39:23: error: undefined name 'missing'

using System;

struct Bag
{
    int Count;
}

void Takes(int[] values)
{
}

int Main()
{
    int[] a = [1, "two", 3];
    Fixed<int, 3> f = [1, 2];
    Bag b = [1, 2];
    int n = [1, 2];
    var e = [];
    var s = [1, ..true];
    string[] w = [..a];
    Takes([1, 2.5]);
    List<string> l = ["a", 1];
    int[][] nested = [[1], ["x"]];
    var m = [1, 2].Lenght;
    Console.WriteLine(missing);
    return a.Length + f[0] + n + w.Length + nested.Length;
}
