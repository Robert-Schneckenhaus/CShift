// A by-value interface parameter would be a copy of unknown size.
// expect-error: interface 'IShape' can only be the type of a 'ref' or 'const ref' parameter

interface IShape
{
    double Area();
}

double Area(IShape s)
{
    return s.Area();
}

int Main()
{
    return 0;
}
