// Structs have no constructors, use an initializer.
// expect-error: structs have no constructors
struct Vec2
{
    float X;
    float Y;
}

int Main()
{
    var v = new Vec2(1, 2);
    return 0;
}
