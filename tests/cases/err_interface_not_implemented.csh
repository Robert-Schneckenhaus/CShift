// expect-error: does not implement
interface IShape
{
    float Area();
}

struct Broken : IShape
{
    float Side;
}

int Main()
{
    return 0;
}
