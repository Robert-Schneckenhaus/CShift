// A method called on a 'const ref' parameter (or a field of one) runs on the caller's value directly when it does not
// change 'this', and on a copy when it may: every way of changing it below must leave the caller's value as it was.
// Main returns the number of failed checks; the ARC check makes sure that every reference is released once.
// expect-exit: 0

using System;

struct Point
{
    int X;
    int Y;

    void Move(int dx) { X += dx; }
    int Sum() { return X + Y; }
}

struct Base
{
    int Level;

    void Raise() { Level += 1; }
}

struct Cell
{
    int Value;

    int Get(int i) { return Value + i; }
    void Set(int i, int v) { Value = v; }      // an indexer that changes the struct itself
}

struct Box<T>
{
    T Item;

    void Put(T item) { Item = item; }
    T Take() { return Item; }
}

struct Thing : Base
{
    string Name;
    int Count;
    Point Pos;
    Fixed<int, 2> Pair;
    List<int> Items;
    Cell Slot;
    Box<string> Label;

    // keep 'this'
    string Describe() { return Name + " " + Count.ToString() + " " + Pos.Sum().ToString(); }
    int First() { return Items.Count() > 0 ? Items[0] : -1; }
    void Store(int v) { Items[0] = v; }       // List.Set writes the shared storage, not the struct
    int Total() { return Descend(3); }
    int Descend(int n) { return n == 0 ? Count : Descend(n - 1); }
    int Even(int n) { return n == 0 ? 1 : Odd(n - 1); }
    int Odd(int n) { return n == 0 ? 0 : Even(n - 1); }

    // change 'this'
    void Rename() { Name = "renamed"; }
    void Bump() { Count += 1; }
    void Step() { Pos.Move(5); }
    void SetPair() { Pair[1] = 9; }
    void Indirect() { Bump(); }
    void Grow() { Items.Add(7); }               // creates the list the first time
    void SetSlot() { Slot[0] = 4; }
    void ByRef() { Twice(ref Count); }
    void Replace() { this = Thing { Name = "other" }; }
    void Promote() { Raise(); }
    void Relabel() { Label.Put("new"); }
    int Ping(int n) { return n == 0 ? 0 : Pong(n - 1); }
    int Pong(int n)
    {
        Count = 100;
        return Ping(n);
    }
    void Poke()
    {
        unsafe
        {
            int* p = &Count;
            *p = 50;
        }
    }
}

void Twice(ref int v)
{
    v *= 2;
}

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

int Reads(const ref Thing t)
{
    int f = 0;
    f += Check("describe", t.Describe() == "thing 3 3");
    f += Check("first", t.First() == 1);
    f += Check("total", t.Total() == 3);
    f += Check("even", t.Even(4) == 1 && t.Odd(3) == 1);
    f += Check("field method", t.Pos.Sum() == 3 && t.Label.Take() == "label");
    f += Check("indexer", t.Slot[2] == 3);
    t.Store(1);
    return f;
}

void Changes(const ref Thing t)
{
    t.Rename();
    t.Bump();
    t.Step();
    t.SetPair();
    t.Indirect();
    t.SetSlot();
    t.ByRef();
    t.Promote();
    t.Relabel();
    t.Ping(3);
    t.Poke();
    t.Pos.Move(1);
    t.Label.Put("other");
    t.Replace();
}

void GrowLazy(const ref Thing t)
{
    t.Grow();
}

int Main()
{
    int f = 0;
    var items = List<int>.Create();
    items.Add(1);
    var t = Thing { Name = "thing", Count = 3, Pos = Point { X = 1, Y = 2 }, Items = items, Slot = Cell { Value = 1 },
                    Label = Box<string> { Item = "label" } };
    f += Reads(t);
    Changes(t);
    f += Check("unchanged", t.Name == "thing" && t.Count == 3 && t.Pos.X == 1 && t.Pair[1] == 0 && t.Slot.Value == 1 &&
                            t.Level == 0 && t.Label.Item == "label");
    var lazy = Thing { Name = "lazy" };
    GrowLazy(lazy);
    f += Check("lazy list stays empty", lazy.Items.Count() == 0);
    GrowLazy(t);
    f += Check("shared list", t.Items.Count() == 2);
    return f;
}
