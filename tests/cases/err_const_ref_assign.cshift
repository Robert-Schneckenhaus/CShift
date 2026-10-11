// expect-error: cannot assign to a read-only value
struct Vec2
{
    float X;
    float Y;
}

void Reset(const ref Vec2 v)
{
    v.X = 0;
}

int Main()
{
    var v = new Vec2();
    Reset(v);
    return 0;
}
