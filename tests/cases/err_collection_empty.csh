// An empty collection without a type has no element type.
// expect-error: cannot infer the type of '[]' here; give it a type (e.g. int[] a = [];)

using System;

int Main()
{
    var nothing = [];
    return 0;
}
