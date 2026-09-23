// Cancel / CancelAndWait / IsCancelled / IsCompleted / Thread.Cancelled, and SharedPtr<T> as a thread parameter.
// expect-exit: 0
// expect-stdout: cancelled=true
// expect-stdout: completed=true
// expect-stdout: result=-1
// expect-stdout: is did not match
// expect-stdout: shared=42
// expect-stdout: plain=20

using System;

// Only cancellation can ever end this loop, so waiting for it (CancelAndWait) is never a race.
thread int CountUp()
{
    while (true)
    {
        if (Thread.Cancelled)
            return -1;
    }
}

thread int AddOne(SharedPtr<int> box)
{
    return box.Get() + 1;
}

thread int Double(int x)
{
    return x * 2;
}

void Main()
{
    Thread<int> counting = CountUp();
    counting.Cancel();
    counting.CancelAndWait();
    Console.WriteLine("cancelled=" + counting.IsCancelled().ToString());
    Console.WriteLine("completed=" + counting.IsCompleted().ToString());
    Console.WriteLine("result=" + counting.Join().ToString());
    if (counting is int r)
        Console.WriteLine("is matched (unexpected): " + r.ToString());
    else
        Console.WriteLine("is did not match (expected)");

    var box = SharedPtr<int>.Create(41);
    Thread<int> shared = AddOne(box);
    Console.WriteLine("shared=" + shared.Join().ToString());

    Thread<int> plain = Double(10);
    Console.WriteLine("plain=" + plain.Join().ToString());
}
