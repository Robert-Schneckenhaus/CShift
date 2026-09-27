// expect-exit: 101
// expect-stderr: panic: List index out of range (index 4, count 2)
// expect-stderr: list.csh:
// expect-stderr:   called from
// expect-stderr: panic_library_caller.csh:13:22 in Pick
// arc-ignore
// A panic inside the standard library also shows where the program called it (here through a callback of the
// library, which calls the library again).
using System;

int Pick(List<int> values, int index)
{
    return values.Get(index);
}

int Main()
{
    var list = List<int>.Create();
    list.Add(1);
    list.Add(2);
    int n = list.Get(0);
    var found = list.Where(x => Pick(list, x + 3) > 0);
    return n + found.Count();
}
