// expect-error: constants can only be numbers, bool, char, string or enum values
struct Point
{
    int X;
}

const Point Origin = new Point();

int Main()
{
    return 0;
}
