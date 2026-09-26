// An interface cannot be a type argument (List<IShape> would hold values of it).
// expect-error: interface 'IShape' can only be the type of a 'ref' or 'const ref' parameter

using System;

interface IShape
{
    double Area();
}

int Main()
{
    var shapes = List<IShape>.Create();
    return 0;
}
