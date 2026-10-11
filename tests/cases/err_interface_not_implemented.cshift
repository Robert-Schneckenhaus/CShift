// Only a struct that lists the interface can be passed as it.
// expect-error: cannot convert 'Point' to 'const ref IShape'

interface IShape
{
    double Area();
}

struct Point
{
    double X;
    double Area() { return 0.0; }
}

double Area(const ref IShape s)
{
    return s.Area();
}

int Main()
{
    var p = Point { X = 1.0 };
    return (int)Area(p);
}
