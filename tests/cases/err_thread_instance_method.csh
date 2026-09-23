// 'thread' cannot be used on an instance method: it would implicitly see 'this'.
// expect-error: not an instance method

using System;

struct Worker
{
    int Value;

    thread void Run()
    {
        Value += 1;
    }
}

void Main()
{
    var w = Worker { Value = 1 };
    w.Run().Join();
}
