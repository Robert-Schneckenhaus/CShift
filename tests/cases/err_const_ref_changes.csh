// Calling a method that changes the struct on a read-only value - a 'const ref' parameter, a field of one, a variable
// that a lambda captured - is an error that says what the method does. Every way of changing 'this' is one.
// expect-error: err_const_ref_changes.csh:125:7: error: 'Rename' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it assigns 'Name'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:126:7: error: 'Bump' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it assigns 'Count'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:127:7: error: 'Step' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it calls 'Move', which assigns 'X'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:128:7: error: 'SetPair' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it assigns 'Pair[...]'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:129:7: error: 'Indirect' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it calls 'Bump', which assigns 'Count'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:130:7: error: 'SetSlot' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it calls 'Set', which assigns 'Value'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:131:7: error: 'ByRef' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it passes 'Count' with 'ref'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:132:7: error: 'Promote' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it calls 'Raise', which assigns 'Level'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:133:7: error: 'Relabel' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it calls 'Put', which assigns 'Item'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:134:7: error: 'Ping' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it calls 'Pong', which assigns 'Count'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:135:7: error: 'Poke' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it takes the address of 'Count'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:136:11: error: 'Move' changes the read-only 'Point' it is called on (a 'const ref' parameter or a variable a lambda captured): it assigns 'X'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:137:13: error: 'Put' changes the read-only 'Box<string>' it is called on (a 'const ref' parameter or a variable a lambda captured): it assigns 'Item'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:138:7: error: 'Fresh' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it assigns 'Items'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:139:7: error: 'Replace' changes the read-only 'Thing' it is called on (a 'const ref' parameter or a variable a lambda captured): it assigns 'this'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:140:15: error: 'Set' changes the read-only 'Cell' it is called on (a 'const ref' parameter or a variable a lambda captured): it assigns 'Value'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:145:10: error: 'Rename' changes the read-only 'Item' it is called on (a 'const ref' parameter or a variable a lambda captured): it calls 'Rename', which assigns 'Name'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'
// expect-error: err_const_ref_changes.csh:151:27: error: 'Move' changes the read-only 'Point' it is called on (a 'const ref' parameter or a variable a lambda captured): it assigns 'X'. Call it on a copy ('var copy = ...;') or make the parameter 'ref'

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
    void Grow() { Items.Add(7); }               // so does List.Add
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
    void Fresh() { Items = [8]; }
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

interface IRenamed
{
    void Rename(int i);
}

struct Named : IRenamed
{
    string Name;

    void Rename(int i) { Name = "renamed " + i.ToString(); }
}

union Item : IRenamed { Named }

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
    t.Fresh();
    t.Replace();
    t.Slot[1] = 2;
}

void ChangesUnion(const ref Item item)
{
    item.Rename(2);
}

int Main()
{
    var p = Point { X = 1 };
    Action move = () => p.Move(1);
    move();
    return 0;
}
