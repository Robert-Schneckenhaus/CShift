// Structs are not yet passed by value to C functions (the C ABI needs per-target coercion).
// expect-error: by value to C is not supported
struct Vec2
{
    float X;
    float Y;
}

extern "C" float length(Vec2 v);

int Main()
{
    var v = new Vec2();
    float l = length(v);
    return 0;
}
