// expect-error: does not satisfy the constraint
struct Plain
{
    int X;
}

T Max<T>(T a, T b)
    where T : IComparable<T>
{
    if (a.CompareTo(b) > 0)
        return a;
    return b;
}

int Main()
{
    var p = Max(new Plain(), new Plain());
    return 0;
}
