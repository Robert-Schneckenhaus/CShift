// Top-level constants and default(T).
// expect-exit: 0

namespace Config;

using System;

const int Size = 4;
const int Negative = -7;
const int64 Big = 5000000000;
const double Ratio = 0.5;
const float Scale = 2.5;
const string Name = "cfg";
const bool Enabled = true;
const char Letter = 'x';
const int Mask = 0xF0 | 0x0F;
const int Computed = 3 * (Size + 1) - 2;

struct Pair
{
    int A;
    string B;
}

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

int Classify(int value)
{
    switch (value)
    {
        case Size:
            return 1;
        case Negative:
            return 2;
        default:
            return 0;
    }
}

int Main()
{
    int f = 0;

    f += Check("int", Size == 4 && Negative == -7 && Mask == 255);
    f += Check("int64", Big == 5000000000);
    f += Check("double/float", Ratio == 0.5 && Scale == 2.5f);
    f += Check("string", Name == "cfg" && Name.Length == 3);
    f += Check("bool/char", Enabled && Letter == 'x');
    f += Check("qualified", Config.Size == 4 && Config.Name == "cfg" && Math.PI > 3.14 && Math.PI < 3.15);
    f += Check("in expressions", Size * 2 == 8 && Ratio * Size == 2);
    f += Check("Computed", Computed == 13);
    f += Check("array size", new int[Size].Length == 4);
    f += Check("switch labels", Classify(4) == 1 && Classify(-7) == 2 && Classify(5) == 0);

    // ---- default(T) ----
    f += Check("default numbers", default(int) == 0 && default(double) == 0 && default(char) == 0);
    f += Check("default bool", !default(bool));
    string s = default(string);
    f += Check("default string", s == null);
    var arr = default(int[]);
    f += Check("default array", arr == null && arr.Length == 0);
    var pair = default(Pair);
    f += Check("default struct", pair.A == 0 && pair.B == null);
    f += Check("default Optional", default(Optional<int>) == null);
    var list = List<string>.Create();
    list.Add("keep");
    list.Add("remove");
    list.RemoveAt(1);
    f += Check("default in generic code", list.Count() == 1 && list.Get(0) == "keep");

    return f;
}
