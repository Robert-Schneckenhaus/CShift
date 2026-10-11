// 'x is not P' negates a pattern, for every kind of subject (Error<T>, Optional<T>, Error<Optional<T>>, unions,
// interfaces). 'x is null' / 'x is not null' compare with null. A binding of 'is not' ('if (x is not T v)') is
// assigned where the pattern matched: in the 'else' branch, and after the 'if' when its branch cannot complete.
// expect-exit: 0
// expect-stdout: false true false true
// expect-stdout: false true true false
// expect-stdout: 40 -1 s3 none
// expect-stdout: no text for -1
// expect-stdout: no text for 0
// expect-stdout: got v1
// expect-stdout: got v2
// expect-stdout: error neg -5
// expect-stdout: not saved
// expect-stdout: union: rect 6
// expect-stdout: a rect of width 2
// expect-stdout: inner 7

using System;

interface IShape
{
    string Name();
}

struct Circle : IShape
{
    double R;
    string Name() { return "circle"; }
}

struct Rect : IShape
{
    double W;
    string Name() { return "rect"; }
}

union Shape : IShape { Circle, Rect }

Error<int> P(int x) { if (x < 0) return error("neg " + x.ToString(), 2); return x; }
Optional<string> O(int x) { if (x < 0) return null; return "s" + x.ToString(); }
Error<Optional<string>> F(int x) { if (x < 0) return error("neg"); if (x == 0) return null; return "v" + x.ToString(); }
Error<void> Save(bool ok) { if (!ok) return error("full"); return; }

int Times10(int x)
{
    if (P(x) is not int v)
        return -1;
    return v * 10;
}

string Text(int x)
{
    if (O(x) is not string s)
        return "none";
    return s;
}

string Kind(const ref IShape shape)
{
    if (shape is not Rect r)
        return "not a rect";
    return "a rect of width " + r.W.ToString();
}

int Main()
{
    Console.WriteLine($"{P(1) is not int} {P(-1) is not int} {P(-1) is not error} {P(1) is not error}");
    Console.WriteLine($"{O(1) is null} {O(-1) is null} {O(1) is not null} {O(-1) is not null}");
    Console.WriteLine(Times10(4).ToString() + " " + Times10(-4).ToString() + " " + Text(3) + " " + Text(-3));

    for (var i = -1; i <= 2; i += 1)
    {
        if (F(i) is not string s)
        {
            Console.WriteLine("no text for " + i.ToString());
            continue;
        }
        Console.WriteLine("got " + s);
    }

    if (P(-5) is not error e)
        Console.WriteLine("ok");
    else
        Console.WriteLine("error " + e.Message);

    if (Save(false) is not error)
        Console.WriteLine("saved");
    else
        Console.WriteLine("not saved");

    Shape shape = Rect { W = 6.0 };
    if (shape is not Rect r)
        Console.WriteLine("not a rect");
    else
        Console.WriteLine("union: " + shape.Name() + " " + r.W.ToString());
    Rect rect = Rect { W = 2.0 };
    Console.WriteLine(Kind(rect));

    bool always = true;
    if (always)
    {
        if (P(7) is not int w)
            return 1;
        else
            Console.WriteLine("inner " + w.ToString());
    }
    return 0;
}
