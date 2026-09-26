// An interface parameter cannot be copied into a variable (it could outlive the struct it points to).
// expect-error: 'copy' cannot hold the interface parameter

interface IShape
{
    double Area();
}

double Area(const ref IShape s)
{
    var copy = s;
    return 0.0;
}

int Main()
{
    return 0;
}
