// Appending to a string writes in place when the string's block has no other reference (x += e, x = x + e ..., and
// the temporaries of a + b + c). Nothing that refers to the old text may see a change: copies, slices, parameters,
// lambdas, foreach. Main returns the number of failed checks; the ARC check makes sure nothing leaks.
// expect-exit: 0

using System;

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

string Suffixed(string p)
{
    p += "-x";          // the caller's string stays as it is
    return p;
}

void AppendRef(ref string p)
{
    p += "!";
}

string Global = "g";

int Main()
{
    int f = 0;

    // a loop of appends
    string text = "";
    for (var i = 0; i < 3000; i += 1)
        text += "line " + i.ToString() + "\n";
    f += Check("loop length", text.Length == 3000 * 6 + 10 * 1 + 90 * 2 + 900 * 3 + 2000 * 4);
    f += Check("loop start", text.StartsWith("line 0\nline 1\n"));
    f += Check("loop end", text.EndsWith("line 2999\n"));

    // x = x + e1 + e2, and every kind of value
    string s = "a";
    s = s + 1 + 'c' + 2.5 + true;
    s += null;
    s += "xyz"[1..];
    s += "";
    f += Check("mixed", s == "a1c2.5Trueyz" || s == "a1c2.5trueyz");

    // a copy, a slice and a lambda keep the old text
    string base0 = "start" + 0.ToString();
    string copy = base0;
    StringSlice part = base0[0..3];
    Func<int> length = () => base0.Length;
    base0 += " more";
    f += Check("copy", copy == "start0" && base0 == "start0 more");
    f += Check("slice", part == "sta");
    f += Check("lambda", length() == 6);

    // the string itself on the right
    string twice = "ab" + "cd";
    twice += twice;
    twice = twice + twice;
    f += Check("self", twice == "abcdabcdabcdabcd");

    // parameters: a copy (the caller's string stays) and 'ref' (the caller's variable changes)
    string arg = "p" + "q";
    string result = Suffixed(arg);
    f += Check("parameter", arg == "pq" && result == "pq-x");
    AppendRef(ref arg);
    f += Check("ref", arg == "pq!");

    // foreach over a string that the loop appends to: the loop sees the old text
    string letters = "x" + "y";
    int seen = 0;
    foreach (var c in letters)
    {
        letters += c.ToString();
        seen += 1;
    }
    f += Check("foreach", seen == 2 && letters == "xyxy");

    // a null string, a constant, a global
    string none = null;
    none += "n";
    f += Check("null", none == "n");
    const string Fixed = "fixed";
    string fromConstant = Fixed;
    fromConstant += "!";
    f += Check("constant", Fixed == "fixed" && fromConstant == "fixed!");
    Global += "h";
    f += Check("global", Global == "gh");

    // temporaries: a + b + c and interpolation
    string joined = "x" + 1.ToString() + "y" + 2.ToString() + "z";
    int n = 7;
    string inter = $"n={n}, twice={n * 2}";
    f += Check("temporaries", joined == "x1y2z" && inter == "n=7, twice=14");

    // a list of strings built from one variable keeps every version
    var list = List<string>.Create();
    string grow = "";
    for (var i = 0; i < 5; i += 1)
    {
        grow += i.ToString();
        list.Add(grow);
    }
    f += Check("list", list[0] == "0" && list[2] == "012" && list[4] == "01234");
    return f;
}
