// Constants: top level and local, numbers, bool, char, string and enums; initializers are constant expressions
// (literals, operators, casts, enum members and other constants). Used before their declaration, too.
// expect-exit: 0
// expect-stdout: consts ok

using System;

enum Color : int { Red, Green = 5, Blue }
enum Flags : uint8 { None = 0, Read = 1, Write = 2 }

const int MyConst = 5;
const int Sum = MyConst * 2 + Later;    // Later is declared below
const int Later = 1;
const uint8 Small = 200;
const int64 Big = 5000000000;
const double Pi = 3.14159;
const float Half = 0.5f;
const bool Flag = true && !false;
const char Letter = 'x';
const string Text = "hi" + "!";
const string Alias = Text;
const Color Fav = Color.Green;
const Color Next = (Color)6;
const Flags ReadWrite = Flags.Read | Flags.Write;
const int Shifted = 1 << 4;
const int Converted = (int)Small + 1;

struct Box
{
    int Value;

    int Scaled()
    {
        const int Factor = 3;
        return Value * Factor;
    }
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
    failed += Check("int", MyConst == 5 && Sum == 11 && Later == 1);
    failed += Check("small and big", Small == 200 && Big == 5000000000);
    failed += Check("floating point", Pi > 3.14 && Pi < 3.15 && Half == 0.5f);
    failed += Check("bool and char", Flag && Letter == 'x');
    failed += Check("string", Text == "hi!" && Alias == "hi!" && Text.Length == 3);
    failed += Check("enum", Fav == Color.Green && Next == Color.Blue && (int)Fav == 5);
    failed += Check("flags", ReadWrite == (Flags)3 && (ReadWrite & Flags.Write) == Flags.Write);
    failed += Check("operators and casts", Shifted == 16 && Converted == 201);

    // local constants
    const int Limit = 4;
    const int Double = Limit * 2 + MyConst;
    const string Prefix = "n" + Text;
    const Color Local = Color.Red;
    failed += Check("local", Limit == 4 && Double == 13 && Prefix == "nhi!" && Local == Color.Red);

    int[] values = new int[Limit];
    for (var i = 0; i < Limit; i += 1)
        values[i] = i * Limit;
    failed += Check("array size", values.Length == 4 && values[3] == 12);

    {
        const int Limit = 100; // an inner scope may hide a constant
        failed += Check("shadow", Limit == 100);
    }
    failed += Check("after shadow", Limit == 4);

    // the initializer of a top-level constant does not see the locals of the function that uses it
    int Later = 50;
    failed += Check("hidden locals", Sum == 11 && Later == 50);

    failed += Check("method", new Box { Value = 7 }.Scaled() == 21);
    if (failed == 0)
        Console.WriteLine("consts ok");
    return failed;
}
