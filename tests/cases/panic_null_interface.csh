// Calling a method of a null interface value panics.
// expect-exit: 101
// expect-stderr: call of a method of a null interface value

interface IShape
{
    double Area();
}

int Main()
{
    IShape s = null;
    return (int)s.Area();
}
