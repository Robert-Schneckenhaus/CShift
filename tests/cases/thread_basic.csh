// The 'thread' keyword and Thread / Thread<T>: 'start', Join, and the 'is' pattern.
// expect-exit: 0
// expect-stdout: 5
// expect-stdout: 3
// expect-stdout: 3
// expect-stdout: done

using System;

thread void SayIt(int x)
{
    Console.WriteLine(x);
}

thread int Sum(int x, int y)
{
    return x + y;
}

void Main()
{
    Thread hello = start SayIt(5);
    Thread<int> sum = start Sum(1, 2);

    hello.Join();
    int result = sum.Join();
    Console.WriteLine(result);

    // Non-blocking: the thread has already finished by now, so this matches.
    if (sum is int again)
        Console.WriteLine(again);
    else
        Console.WriteLine("no result (unexpected)");

    // Chaining a method directly off 'start ...' (note: a fire-and-forget 'start Foo(x);' with no matching Join
    // is intentionally not exercised here - the process can exit before a never-joined thread finishes, which
    // would make the '--arc-stats' leak check below flaky by design, not by bug).
    int chained = (start Sum(4, 4)).Join();
    Console.WriteLine(chained);

    Console.WriteLine("done");
}
