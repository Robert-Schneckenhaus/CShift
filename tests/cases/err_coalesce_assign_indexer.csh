// '??=' works on variables, fields and array elements, not on the indexer of a struct (Get/Set).
// expect-error: '??=' does not work with an indexer (x[k] of a struct)
using System;

int Main()
{
    var slots = List<Optional<int>>.Create();
    slots.Add(null);
    slots[0] ??= 1;
    return 0;
}
