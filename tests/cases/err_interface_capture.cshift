// A lambda cannot use an interface parameter (the lambda could outlive the struct).
// expect-error: a lambda cannot use the interface parameter 's'

using System;

interface IShape
{
    double Area();
}

Func<double> Later(const ref IShape s)
{
    return () => s.Area();
}

int Main()
{
    return 0;
}
