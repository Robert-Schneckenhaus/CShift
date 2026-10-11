// new without a type needs a declared type
// expect-error: 'new' without a type needs a struct type to take
struct Player
{
    int X;
}

int Main()
{
    var p = new { X = 1 };
    return p.X;
}
