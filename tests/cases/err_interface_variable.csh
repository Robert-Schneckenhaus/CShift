// Interfaces cannot be used as value types (no boxing); they are constraints and base lists only.
// expect-error: can only be used as a generic constraint
interface IShape
{
    float Area();
}

int Main()
{
    IShape s;
    return 0;
}
