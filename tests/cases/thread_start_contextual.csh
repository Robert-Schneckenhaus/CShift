// 'start' is a contextual keyword: it must still work as an ordinary identifier (variable, parameter, field)
// everywhere it isn't immediately followed by another identifier.
// expect-exit: 0
// expect-stdout: 7
// expect-stdout: 3
// expect-stdout: 36

using System;

struct Range
{
    int start;
    int count;

    int End()
    {
        return start + count;
    }
}

int Sum(int start, int count)
{
    return start + count;
}

thread int Square(int x)
{
    return x * x;
}

void Main()
{
    int start = 3;
    int count = 4;
    Console.WriteLine(Sum(start, count));

    var r = Range { start = 1, count = 2 };
    Console.WriteLine(r.End());

    // The real keyword still works right next to an identifier-named variable in scope.
    Thread<int> t = start Square(6);
    Console.WriteLine(t.Join());
}
