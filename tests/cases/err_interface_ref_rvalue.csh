// 'ref IShape' needs a variable passed with 'ref' (the callee changes it).
// expect-error: cannot convert 'Circle' to 'ref IShape' (pass it with 'ref')

interface IShape
{
    void Grow();
}

struct Circle : IShape
{
    double R;
    void Grow() { R = R * 2.0; }
}

void Enlarge(ref IShape s)
{
    s.Grow();
}

int Main()
{
    var c = Circle { R = 1.0 };
    Enlarge(c);
    return 0;
}
