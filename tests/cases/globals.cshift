// Global variables: zero values, initializers (run before Main in the order of the declarations), strings and
// collections (released at the end of the program), structs, function pointers, ref and address-of.
// expect-exit: 0
// expect-stdout: globals ok

using System;

struct Point
{
    int X;
    int Y;
    string Label;
}

int Counter;                            // starts with 0
int Start = 40 + 2;                     // any expression
string Title = "title";
string Built = "built-" + Title;        // uses a global that is declared before
string Empty;                           // null
double Ratio = 2.5;
bool Flag = true;
Point Origin = Point { X = 1, Y = 2, Label = "origin" };
List<string> Names = List<string>.Create();
int[] Table = new int[] { 3, 1, 4 };
Func<int, int> Twice = Double;
int UsedBeforeDeclaration = Later + 1;  // Later has no initializer, so it is zero here
int FromFunction = ReadStart() + 1;    // a function that reads an earlier global is fine
int Later;                              // no initializer: may be used before its declaration

int ReadStart()
{
    return Start;
}

int Double(int v)
{
    return v * 2;
}

int Next()
{
    Counter += 1;
    return Counter;
}

void Bump(ref int value)
{
    value += 10;
}

void Remember(string name)
{
    Names.Add(name);
    Empty = name; // replaces the old value
}

int Check(string what, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + what);
    return 1;
}

int Main()
{
    int failed = 0;
    failed += Check("zero", Counter == 0);
    failed += Check("initializer", Start == 42);
    failed += Check("string", Title == "title" && Built == "built-title");
    failed += Check("null string", Empty == null);
    failed += Check("double and bool", Ratio == 2.5 && Flag);
    failed += Check("struct", Origin.X == 1 && Origin.Y == 2 && Origin.Label == "origin");
    failed += Check("array", Table.Length == 3 && Table[1] == 1);
    failed += Check("function pointer", Twice(21) == 42);
    failed += Check("through a function", FromFunction == 43);
    failed += Check("order", UsedBeforeDeclaration == 1 && Later == 0);

    Next();
    Next();
    failed += Check("counter", Counter == 2);
    Counter = Counter * 3;
    Counter += 1;
    failed += Check("assign", Counter == 7);

    Bump(ref Counter);
    failed += Check("ref", Counter == 17);

    Remember("a");
    Remember("b" + Counter.ToString());
    failed += Check("list", Names.Count() == 2 && Names.Get(1) == "b17");
    failed += Check("string replaced", Empty == "b17");

    Origin.X = 9;
    Origin.Label = Origin.Label + "!";
    Table[0] = 7;
    failed += Check("fields", Origin.X == 9 && Origin.Label == "origin!" && Table[0] == 7);

    unsafe
    {
        int* p = &Counter;
        *p = 100;
    }
    failed += Check("address", Counter == 100);

    if (failed == 0)
        Console.WriteLine("globals ok");
    return failed;
}
