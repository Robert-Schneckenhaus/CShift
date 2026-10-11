// A switch without 'default:' over an enum, a union or the codes of an Error<T, E> must handle every case; with all
// cases named it needs no default.
// expect-exit: 0
// expect-stdout: green
// expect-stdout: rect 6
// expect-stdout: io denied

using System;

enum Color : uint8 { Red, Green, Blue, Lime = 1 }

interface IShape { double Area(); }
struct Circle : IShape { double R; double Area() { return 3.0 * R * R; } }
struct Rect : IShape { double W; double H; double Area() { return W * H; } }
union Shape : IShape { Circle, Rect }

error IoError { NotFound, Denied }

IoError<int> Open(bool allowed)
{
    if (!allowed)
        return error(IoError.Denied);
    return 1;
}

string Name(Color c)
{
    switch (c)
    {
        case Color.Red:
            return "red";
        case Color.Green:          // Lime has the same value
            return "green";
        case Color.Blue:
            return "blue";
    }
    return "?";
}

int Main()
{
    Console.WriteLine(Name(Color.Lime));
    Shape s = Rect { W = 2.0, H = 3.0 };
    switch (s)
    {
        case Circle c:
            Console.WriteLine("circle");
            break;
        case Rect r:
            Console.WriteLine("rect " + r.Area());
            break;
    }
    switch (Open(false))
    {
        case int handle:
            Console.WriteLine("open");
            break;
        case IoError.NotFound:
            Console.WriteLine("io not found");
            break;
        case IoError.Denied:
            Console.WriteLine("io denied");
            break;
    }
    return 0;
}
