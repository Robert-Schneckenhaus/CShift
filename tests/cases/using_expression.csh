// using (expr) { ... } without a variable: the value is disposed when the block is left, like a declared one - also by
// return and break, and nested ones in reverse order. A struct that shares its state through a managed reference (here
// a one-element array) can give out such scopes (begin/end pairs: rows of a layout, indentation of output).
// expect-exit: 0
// expect-stdout: open a|open b|item 1|close b|close a|open a|close a|open loop|close loop|done
// expect-stdout: depth 0

using System;

struct _Log
{
    int Depth;
    List<string> Lines;
}

struct Scope : IDisposable
{
    _Log[] S;
    string Name;

    void Dispose()
    {
        S[0].Depth -= 1;
        S[0].Lines.Add("close " + Name);
    }
}

struct Writer
{
    _Log[] S;

    static Writer Create()
    {
        var s = new _Log[1];
        s[0].Lines = List<string>.Create();
        return Writer { S = s };
    }

    Scope Open(string name)
    {
        S[0].Depth += 1;
        S[0].Lines.Add("open " + name);
        return Scope { S = S, Name = name };
    }

    void Add(string line)
    {
        S[0].Lines.Add(line);
    }
}

int Early(Writer w)
{
    using (w.Open("a"))
    {
        return 1; // disposed on the way out
    }
}

int Main()
{
    var w = Writer.Create();
    using (w.Open("a"))
    {
        using (w.Open("b"))
            w.Add("item 1");
    }
    Early(w);
    while (true)
    {
        using (w.Open("loop"))
        {
            break;
        }
    }
    w.Add("done");
    Console.WriteLine(string.Join("|", w.S[0].Lines.ToArray()));
    Console.WriteLine("depth " + w.S[0].Depth.ToString());
    return 0;
}
