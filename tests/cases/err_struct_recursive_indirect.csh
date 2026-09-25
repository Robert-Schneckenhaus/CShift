// expect-error: contains itself by value
struct Outer
{
    int Value;
    Middle Part;
}

struct Middle
{
    Outer Back;
}

int Main()
{
    return 0;
}
