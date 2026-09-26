// An interface is not a value type (a value of it would need a hidden allocation): only a 'ref'/'const ref' parameter.
// expect-error: interface 'IShape' can only be the type of a 'ref' or 'const ref' parameter or a generic constraint

interface IShape
{
    double Area();
}

struct Circle : IShape
{
    double R;
    double Area() { return R; }
}

int Main()
{
    IShape s = Circle { R = 1.0 };
    return 0;
}
