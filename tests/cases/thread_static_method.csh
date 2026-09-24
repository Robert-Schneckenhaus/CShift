// 'thread' on a static struct method.
// expect-exit: 0
// expect-stdout: 99

using System;

struct Calculator
{
    static thread int AddOne(int x)
    {
        return x + 1;
    }
}

void Main()
{
    Thread<int> t = start Calculator.AddOne(98);
    Console.WriteLine(t.Join());
}
