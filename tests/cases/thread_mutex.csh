// Mutex<T>: a counter and a string shared by several threads; guards (using) and Mutex.Get/Set. The result must be exact
// and nothing may leak.
// expect-exit: 0
// expect-stdout: 80000
// expect-stdout: 400
// expect-stdout: 0 0

using System;

thread void Count(Mutex<int> counter, int times)
{
    for (var i = 0; i < times; i += 1)
    {
        using (var guard = counter.Lock())
            guard.Set(guard.Get() + 1);
    }
}

thread void Append(Mutex<string> log, string text, int times)
{
    for (var i = 0; i < times; i += 1)
    {
        using (var guard = log.Lock())
            guard.Set(guard.Get() + text);
    }
}

int Main()
{
    var counter = Mutex<int>.Create(0);
    var threads = List<Thread>.Create();
    for (var i = 0; i < 8; i += 1)
        threads.Add(start Count(counter, 10000));
    foreach (var t in threads)
        t.Join();
    Console.WriteLine(counter.Get());

    var log = Mutex<string>.Create("");
    var t1 = start Append(log, "a", 200);
    var t2 = start Append(log, "b", 200);
    t1.Join();
    t2.Join();
    Console.WriteLine(log.Get().Length);
    var guard = counter.Lock();
    guard.Set(3);
    guard.Dispose();
    guard.Dispose(); // only unlocks once
    counter.Update(n => n * 0 + 3);
    var other = counter; // a handle: copies share the value
    other.Set(0);
    Console.WriteLine(counter.Get().ToString() + " " + other.Get().ToString());
    return 0;
}
