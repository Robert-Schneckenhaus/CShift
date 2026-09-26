// expect-error: constants can only be numbers, bool, char, string, enum values or a ReadOnlySlice<T> of them
struct Point
{
    int X;
}

const Point Origin = new Point();

int Main()
{
    return 0;
}
