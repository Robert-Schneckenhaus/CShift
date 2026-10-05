// A method called on a 'const ref' parameter or on a temporary (a struct or a union) works on a copy. When the method replaces fields of
// that copy, the new values are released at the end of the statement and the old ones are not released twice (the
// caller's value still holds them). Main returns the number of failed checks; the ARC check makes sure that every
// reference is released once.
// expect-exit: 0

using System;

interface IRenamed
{
    void Rename(int i);
    string Text();
}

struct Named : IRenamed
{
    string Name;
    List<int> Items;
    int Hits;

    void Rename(int i)
    {
        Name = "renamed " + i.ToString();
        Hits += 1;
    }

    void Track(int i)
    {
        Items = List<int>.Create();                // replaces the list (in the copy)
        Items.Add(i);
    }

    string Text()
    {
        return Name;
    }
}

union Item : IRenamed { Named }

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

Named Make(int i)
{
    return Named { Name = "made " + i.ToString() };
}

void Change(const ref Named n)
{
    n.Rename(1);
    n.Track(1);
}

void ChangeItem(const ref Item item)
{
    item.Rename(2);
}

Item MakeItem(int i)
{
    return Make(i);
}

int Main()
{
    int f = 0;
    var a = Named { Name = "a " + 1.ToString() };
    Change(a);
    f += Check("const ref keeps the name", a.Name == "a 1");
    f += Check("const ref keeps the count", a.Hits == 0);
    f += Check("const ref keeps the list", a.Items.Count() == 0);

    var b = Named { Name = "b " + 2.ToString(), Items = List<int>.Create() };
    Change(b);
    f += Check("own list", b.Items.Count() == 0 && b.Name == "b 2");

    Item item = Make(5);
    ChangeItem(item);
    f += Check("const ref union keeps the name", item.Text() == "made 5");
    MakeItem(6).Rename(7);                         // a temporary union

    Make(2).Rename(3);                             // a temporary
    Make(4).Track(5);
    for (var i = 0; i < 3; i += 1)
        Make(i).Rename(i);
    return f;
}
