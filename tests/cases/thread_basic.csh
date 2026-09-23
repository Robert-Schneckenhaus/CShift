// The 'thread' keyword and Thread / Thread<T>: spawning, Join, and the 'is' pattern.
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
    Thread hello = SayIt(5);
    Thread<int> sum = Sum(1, 2);

    hello.Join();
    int result = sum.Join();
    Console.WriteLine(result);

    // Non-blocking: the thread has already finished by now, so this matches.
    if (sum is int again)
        Console.WriteLine(again);
    else
        Console.WriteLine("no result (unexpected)");

    Console.WriteLine("done");
}
