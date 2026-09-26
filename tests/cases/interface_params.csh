// Interfaces as 'ref'/'const ref' parameters: dynamic dispatch through a method table, without an allocation. 'ref'
// works on the caller's struct, 'const ref' on a copy the caller makes; 'is' gets the struct back; an interface
// parameter can be passed on; constraints (generics) keep calling directly.
// expect-exit: 0
// expect-stdout: circle: 3
// expect-stdout: rect x: 6 / rect x: 6
// expect-stdout: circle: 12 rect x+: 24
// expect-stdout: 2400
// expect-stdout: rect x+: 24
// expect-stdout: a rect of width 4, not a rect
// expect-stdout: circle: 27
// expect-stdout: circle

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
    void Grow(double factor) { W = W * factor; H = H * factor; Tag = Tag + "+"; }
}

string Describe(const ref IShape shape)
{
    return $"{shape.Name()}: {shape.Area()}";
}

// passes its interface parameter on
string Twice(const ref IShape shape)
{
    return Describe(shape) + " / " + Describe(shape);
}

void Enlarge(ref IShape shape, double factor)
{
    shape.Grow(factor);
}

// const ref: the callee's changes go to a copy
double GrowCopy(const ref IShape shape)
{
    shape.Grow(10.0);
    return shape.Area();
}

string Kind(const ref IShape shape)
{
    if (shape is Rect r)
        return "a rect of width " + r.W.ToString();
    return "not a rect";
}

T Bigger<T>(T a, T b) where T : IShape
{
    return a.Area() >= b.Area() ? a : b;
}

int Main()
{
    var c = Circle { R = 1.0 };
    var r = Rect { W = 2.0, H = 3.0, Tag = "x" };
    Console.WriteLine(Describe(c));
    Console.WriteLine(Twice(r));
    Enlarge(ref c, 2.0);
    Enlarge(ref r, 2.0);
    Console.WriteLine(Describe(c) + " " + Describe(r));
    Console.WriteLine(GrowCopy(r));
    Console.WriteLine(Describe(r));
    Console.WriteLine(Kind(r) + ", " + Kind(c));
    Console.WriteLine(Describe(Circle { R = 3.0 }));
    Console.WriteLine(Bigger(c, Circle { R = 0.5 }).Name());
    return 0;
}
