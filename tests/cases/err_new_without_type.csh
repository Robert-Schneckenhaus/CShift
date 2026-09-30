// new without a type needs a declared type
// expect-error: 'new' without a type needs a declaration with a type to take it from
struct Player
{
    int X;
}

int Main()
{
    var p = new { X = 1 };
    return p.X;
}
