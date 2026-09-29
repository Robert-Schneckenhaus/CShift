// --unchecked: integer overflow wraps around instead of a panic; division by zero still panics (see unchecked_project
// in tests/projects for "unchecked": true in cshift.json).
// options: --unchecked
// expect-stdout: -2147483648
// expect-stdout: 0
// expect-stdout: 4
// expect-stdout: 1
using System;

int Main()
{
    int x = int.MaxValue;
    x += 1;
    Console.WriteLine(x.ToString());
    uint u = 0;
    u -= 1;
    u += 1;
    Console.WriteLine(u.ToString());
    int m = 1 << 30;
    Console.WriteLine((m * 4 + 4).ToString());
    // the standard library is compiled checked as before
    var list = List<int>.Create();
    list.Add(1);
    Console.WriteLine(list.Count().ToString());
    return 0;
}
