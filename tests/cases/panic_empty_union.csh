// A method of an empty union (its default value) panics.
// expect-exit: 101
// expect-stderr: the union 'Shape' holds no value

interface IShape
{
    double Area();
}

struct Circle : IShape
{
    double R;
    double Area() { return R; }
}

union Shape : IShape { Circle }

int Main()
{
    Shape s = default(Shape);
    return (int)s.Area();
}
