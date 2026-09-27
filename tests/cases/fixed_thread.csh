// A Fixed of plain values is copied into a thread like any value.
// expect-exit: 0
// expect-stdout: thread 5

using System;

thread int Sum(Fixed<int, 2> values)
{
    return values[0] + values[1];
}

int Main()
{
    Fixed<int, 2> values = [2, 3];
    var t = start Sum(values);
    Console.WriteLine("thread " + t.Join().ToString());
    return 0;
}
