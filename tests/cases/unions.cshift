// Sum types: union Shape : IShape { Circle, Rect } stores one member inline with a tag - conversion from a member,
// methods of the listed interface dispatched on the tag (in place), passing to ref/const ref IShape, is/switch,
// a List<Shape>, a generic constraint, a union of primitive types, the empty default.
// expect-exit: 0
// expect-stdout: circle 3 rect x 6
// expect-stdout: 21
// expect-stdout: rect x+: 24
// expect-stdout: circle: 12
// expect-stdout: rect 4 x+
// expect-stdout: not a circle
// expect-stdout: rect x+
// expect-stdout: int 42, string hi, bool true, empty
// expect-stdout: false
// expect-stdout: string two

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

union Shape : IShape { Circle, Rect }

// a union without interfaces, of any value types
union Token { int, string, bool }

string Describe(const ref IShape shape)
{
    return $"{shape.Name()}: {shape.Area()}";
}

void Enlarge(ref IShape shape)
{
    shape.Grow(2.0);
}

double Total(List<Shape> shapes)
{
    double sum = 0.0;
    foreach (var s in shapes)
        sum += s.Area();
    return sum;
}

T Bigger<T>(T a, T b) where T : IShape
{
    return a.Area() >= b.Area() ? a : b;
}

string Show(Token t)
{
    switch (t)
    {
        case int i:
            return $"int {i}";
        case string s:
            return $"string {s}";
        case bool b:
            return $"bool {b}";
        default:
            return "empty";
    }
}

int Main()
{
    Shape a = Circle { R = 1.0 };
    Shape b = Rect { W = 2.0, H = 3.0, Tag = "x" };
    Console.WriteLine($"{a.Name()} {a.Area()} {b.Name()} {b.Area()}");
    var shapes = List<Shape>.Create();
    shapes.Add(a);
    shapes.Add(b);
    shapes.Add(Circle { R = 2.0 });
    Console.WriteLine(Total(shapes));
    b.Grow(2.0);                          // in place
    Console.WriteLine(Describe(b));
    Enlarge(ref a);
    Console.WriteLine(Describe(a));
    if (b is Rect r)
        Console.WriteLine("rect " + r.W.ToString() + " " + r.Tag);
    if (!(b is Circle))
        Console.WriteLine("not a circle");
    Console.WriteLine(Bigger(a, b).Name());
    Console.WriteLine(Show(42) + ", " + Show("hi") + ", " + Show(true) + ", " + Show(default(Token)));
    Shape empty = default(Shape);
    Console.WriteLine(empty is Circle);
    var tokens = new Token[] { 1, "two", false };
    Console.WriteLine(Show(tokens[1]));
    return 0;
}
