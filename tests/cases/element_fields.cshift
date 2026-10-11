// Two ways of not copying: 'list.Get(i).Name' (and 'list[i].Name') reads the field where the element is instead of
// copying the whole element first, and a local variable that is a copy of a part of a 'const ref' parameter and is only
// read is an alias of that part. The results must be the same as with copies - also when the list changes later in the
// same expression. Main returns the number of failed checks; the ARC check makes sure that every reference is released
// once.
// expect-exit: 0

using System;

struct Entry
{
    string Name;
    Inner In;
    int Count;
}

struct Inner
{
    string Text;
    List<int> Items;
}

struct Box
{
    List<Entry> Entries;
    string Title;

    int Total()
    {
        int n = 0;
        for (var i = 0; i < Entries.Count(); i += 1)
            n += Entries.Get(i).Count + Entries[i].In.Text.Length;   // fields of 'this'
        return n;
    }
}

string Describe(const ref Box b)
{
    var title = b.Title;                       // only read: an alias of b.Title
    var entries = b.Entries;                   // only read: an alias
    string s = title + ":";
    for (var i = 0; i < entries.Count(); i += 1)
        s += " " + entries.Get(i).Name + "/" + entries[i].In.Text;
    return s;
}

string Changed(const ref Box b)
{
    var title = b.Title;                       // changed below: a copy
    title += "!";
    return title + b.Title;
}

int Main()
{
    var list = List<Entry>.Create();
    for (var i = 0; i < 3; i += 1)
        list.Add(Entry { Name = "e" + i.ToString(), In = Inner { Text = "t" + i.ToString(), Items = [i] }, Count = i });
    var box = Box { Entries = list, Title = "box" };
    int fails = 0;
    if (Describe(box) != "box: e0/t0 e1/t1 e2/t2") fails += 1;
    if (Changed(box) != "box!box") fails += 1;
    if (box.Total() != 3 + 6) fails += 1;
    // the field outlives a change of the list in the same expression
    string kept = list.Get(0).Name + Drop(list);
    if (kept != "e0dropped" || list.Count() != 2) fails += 1;
    if (list[1].In.Items[0] != 2) fails += 1;
    return fails;
}

string Drop(List<Entry> l)
{
    l.RemoveAt(0);
    return "dropped";
}
