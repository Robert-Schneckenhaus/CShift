// The last use of a local variable gives its reference away (no retain now, no release later): return x, y = x,
// var y = x, the fields of a struct initializer and the items of a collection expression there. A variable that is
// used again - later in the block, in the next turn of a loop, twice in the statement, through '&' or a lambda - keeps
// its value. Main returns the number of failed checks; the ARC check makes sure that every reference is released once.
// expect-exit: 0

using System;

struct Pair
{
    string A;
    string B;
}

struct Holder : IDisposable
{
    List<int> Items;

    void Dispose()
    {
        Items.Clear();
    }
}

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

string Fresh(string text)
{
    return text + "!";
}

List<int> Build(int n)
{
    var list = List<int>.Create();
    for (var i = 0; i < n; i += 1)
        list.Add(i);
    return list;                                   // moved
}

string Param(string p)
{
    return p;                                      // a parameter is moved as well
}

Pair MakePair(string a)
{
    string b = Fresh("b");
    return Pair { A = a, B = b };                  // both moved
}

Pair Twice(string a)
{
    return Pair { A = a, B = a };                  // used twice: copied
}

string[] Items(string a, string b)
{
    return [a, b, a + b];
}

Error<string> Wrapped(int n)
{
    string text = Fresh(n.ToString());
    return text;                                   // moved into the result
}

int Main()
{
    int f = 0;
    f += Check("return", Build(5).Count() == 5);
    f += Check("parameter", Param(Fresh("p")) == "p!");
    var pair = MakePair(Fresh("a"));
    f += Check("struct", pair.A == "a!" && pair.B == "b!");
    var twice = Twice(Fresh("t"));
    f += Check("twice", twice.A == "t!" && twice.B == "t!");
    var items = Items(Fresh("x"), Fresh("y"));
    f += Check("collection", items.Length == 3 && items[2] == "x!y!");
    f += Check("result", Wrapped(3) is string w && w == "3!");

    // y = x and var y = x: moved only when x is not used again
    string x = Fresh("x");
    string y = x;                                  // x is used below: copied
    f += Check("copy kept", x == "x!" && y == "x!");
    string z = Fresh("z");
    var moved = z;                                 // last use: moved
    f += Check("moved", moved == "z!");

    // loops: a variable from outside is read again in the next turn; one declared inside is not
    string outside = Fresh("o");
    string last = "";
    for (var i = 0; i < 3; i += 1)
    {
        last = outside;
        string inside = Fresh(i.ToString());
        last = last + inside;
        string keep = inside;
        f += Check("inside " + i.ToString(), keep == i.ToString() + "!");
    }
    f += Check("outside", outside == "o!" && last == "o!2!");

    // a lambda that uses the variable later keeps it
    string captured = Fresh("c");
    string other = captured;
    Func<int> len = () => captured.Length;
    f += Check("lambda", other == "c!" && len() == 2);

    // branches and an inner block that declares the same name
    string branch = Fresh("b");
    string chosen = "";
    if (branch.Length > 1)
        chosen = branch;
    else
        chosen = "none";
    f += Check("branch", chosen == "b!");
    string shadow = Fresh("s");
    {
        string inner = Fresh("i");
        string got = inner;
        f += Check("block", got == "i!");
    }
    f += Check("after block", shadow == "s!");

    // switch sections
    string word = Fresh("w");
    string picked = "";
    switch (word.Length)
    {
    case 2:
        picked = word;
        break;
    default:
        picked = "?";
        break;
    }
    f += Check("switch", picked == "w!");

    // 'using' variables are disposed at the end of their scope, never moved
    using var holder = Holder { Items = Build(2) };
    var alias = holder;
    f += Check("using", alias.Items.Count() == 2);

    // a variable whose address is taken is not moved
    unsafe
    {
        string target = Fresh("t");
        string* p = &target;
        string copy = target;
        f += Check("address", *p == "t!" && copy == "t!");
    }
    return f;
}
