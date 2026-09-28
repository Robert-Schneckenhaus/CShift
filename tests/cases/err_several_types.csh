// Unknown type names in declarations and bodies, all in one run; nothing that depends on them is reported again.
// expect-error: err_several_types.csh:43:14: error: unknown type 'Wrong'
// expect-error: err_several_types.csh:45:7: error: unknown type 'Nope'
// expect-error: err_several_types.csh:47:1: error: unknown type 'Glob'
// expect-error: err_several_types.csh:22:5: error: unknown type 'Nope'
// expect-error: err_several_types.csh:23:10: error: unknown type 'Nope'
// expect-error: err_several_types.csh:49:1: error: unknown type 'Nope'
// expect-error: err_several_types.csh:49:28: error: unknown type 'Nope'
// expect-error: err_several_types.csh:33:5: error: unknown type 'Zed'
// expect-error: err_several_types.csh:34:15: error: unknown type 'Nope'
// expect-error: err_several_types.csh:57:5: error: unknown type 'Baz'
// expect-error: err_several_types.csh:58:21: error: unknown type 'Baz'
// expect-error: err_several_types.csh:60:10: error: unknown type 'Baz'
// expect-error: err_several_types.csh:61:14: error: unknown type 'Baz'
// expect-error: err_several_types.csh:29:15: error: unknown type 'Qux'
// expect-error: err_several_types.csh:69:17: error: cannot implicitly convert 'string' to 'int32'

using System;

struct Holder
{
    Nope A;
    List<Nope> B;
    int C;

    int Get() { return C + A.X + B.Count(); }
}

union Value { Qux, string }

interface IShape
{
    Zed Area();
    int Sides(Nope n);
}

struct Square : IShape
{
    int Area() { return 1; }
    int Sides(int n) { return 4; }
}

enum Level : Wrong { Low, High }

const Nope Limit = 3;
const int Twice = Limit * 2;
Glob counter = 3;

Nope[] Many() { return new Nope[2]; }

int Measure(ref IShape s) { return s.Sides(1); }

int Main()
{
    var h = Holder { C = 1 };
    var m = Many();
    Baz local = m[0];
    var list = List<Baz>.Create();
    list.Add(local);
    Func<Baz, int> f = x => 1;
    var q = (Baz)3;
    Value v = "text";
    switch (v)
    {
    case string s:
        break;
    }
    var sq = Square { };
    int wrong = "s";
    return h.Get() + f(local) + Twice + Measure(ref sq) + (int)Level.Low + counter;
}
