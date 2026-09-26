// A struct converts to an interface value only if it lists the interface.
// expect-error: cannot implicitly convert 'Point' to 'IShape'

interface IShape
{
    double Area();
}

struct Point
{
    double X;
    double Area() { return 0.0; }
}

int Main()
{
    IShape s = Point { X = 1.0 };
    return 0;
}
