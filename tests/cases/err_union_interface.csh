// Every member of a union has to implement the interfaces the union lists.
// expect-error: 'Point' does not implement 'IShape', so union 'Shape' cannot list it

interface IShape
{
    double Area();
}

struct Circle : IShape
{
    double R;
    double Area() { return R; }
}

struct Point
{
    double X;
}

union Shape : IShape { Circle, Point }

int Main()
{
    Shape s = Circle { R = 1.0 };
    return 0;
}
