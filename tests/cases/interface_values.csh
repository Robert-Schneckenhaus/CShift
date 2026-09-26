// Interface values: dynamic dispatch through a method table, a boxed copy of the struct shared by copies of the
// interface value, 'is' to get the struct back, null, List<IShape>, an interface value for a generic constraint.
// expect-exit: 0
// expect-stdout: circle 3 rect x 6
// expect-stdout: 21
// expect-stdout: 12
// expect-stdout: rect 2
// expect-stdout: not a circle
// expect-stdout: true true
// expect-stdout: circle
// expect-stdout: 6

using System;

interface IShape
{
    double Area();
    string Name();
    void Grow(double factor);
}

struct Circle : IShape
{
    double R;
    double Area() { return 3.0 * R * R; }
    string Name() { return "circle"; }
    void Grow(double factor) { R = R * factor; }
}

struct Rect : IShape
{
    double W;
    double H;
    string Tag;
    double Area() { return W * H; }
    string Name() { return "rect " + Tag; }
    void Grow(double factor) { W = W * factor; H = H * factor; }
}

double Total(List<IShape> shapes)
{
    double sum = 0.0;
    foreach (var s in shapes)
        sum += s.Area();
    return sum;
}

T Biggest<T>(T a, T b) where T : IShape
{
    return a.Area() >= b.Area() ? a : b;
}

int Main()
{
    IShape a = Circle { R = 1.0 };
    IShape b = Rect { W = 2.0, H = 3.0, Tag = "x" };
    Console.WriteLine($"{a.Name()} {a.Area()} {b.Name()} {b.Area()}");
    var shapes = List<IShape>.Create();
    shapes.Add(a);
    shapes.Add(b);
    shapes.Add(Circle { R = 2.0 });
    Console.WriteLine(Total(shapes));
    IShape copy = a;
    copy.Grow(2.0);            // the box is shared
    Console.WriteLine(a.Area());
    if (b is Rect r)
        Console.WriteLine("rect " + r.W.ToString());
    if (!(b is Circle))
        Console.WriteLine("not a circle");
    IShape none = null;
    Console.WriteLine((none == null).ToString() + " " + (a != null).ToString());
    Console.WriteLine(Biggest(a, b).Name());
    Func<IShape, double> area = s => s.Area();
    Console.WriteLine(area(b));
    return 0;
}
