// List<T> with functions: ForEach, Where, Select<U>, Any, All, FindIndex (with lambdas).
// expect-exit: 0
// expect-stdout: 4
// expect-stdout: 6
// expect-stdout: #6
// expect-stdout: true true 3

using System;
int Main()
{
    var list = List<int>.Create();
    for (var i = 1; i <= 6; i += 1)
        list.Add(i);
    int limit = 3;
    var big = list.Where(x => x > limit);
    big.ForEach(x => Console.WriteLine(x));
    var names = list.Select<string>(x => $"#{x}");
    Console.WriteLine(names[5]);
    Console.WriteLine(list.Any(x => x == 4).ToString() + " " + list.All(x => x > 0).ToString() + " " + list.FindIndex(x => x * x > 10).ToString());
    return 0;
}
