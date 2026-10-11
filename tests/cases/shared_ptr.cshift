// SharedPtr<T>: an atomically reference-counted box (usable on its own, not only with threads).
// expect-exit: 0
// expect-stdout: 41
// expect-stdout: 42
// expect-stdout: null
// expect-stdout: not null
// expect-stdout: hello
// expect-stdout: 1,2

using System;

struct Point { int X; int Y; }

void Main()
{
    SharedPtr<int> p = SharedPtr<int>.Create(41);
    Console.WriteLine(p.Get());

    // Copies share the same box.
    SharedPtr<int> p2 = p;
    unsafe
    {
        int* raw = p2.Ptr();
        *raw = *raw + 1;
    }
    Console.WriteLine(p.Get());

    SharedPtr<int> n = null;
    Console.WriteLine(n.IsNull() ? "null" : "not null");
    Console.WriteLine(p.IsNull() ? "null" : "not null");

    SharedPtr<string> s = SharedPtr<string>.Create("hello");
    Console.WriteLine(s.Get());

    SharedPtr<Point> pt = SharedPtr<Point>.Create(Point { X = 1, Y = 2 });
    Console.WriteLine(pt.Get().X.ToString() + "," + pt.Get().Y.ToString());
}
