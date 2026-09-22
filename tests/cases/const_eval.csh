// The compile-time evaluator: constants are computed by the compiler with the rules of the run-time code. Every
// constant is compared with the same expression evaluated at run time from variables.
// expect-exit: 0
// expect-stdout: const_eval ok

using System;

enum Color : int { Red, Green = 5, Blue }
enum Flags : uint8 { None = 0, Read = 1, Write = 2, Both = Read | Write, Shifted = 1 << 3 }
const int K = 3;
enum FromConst : int { A = K * 2, B, C = A + K, D = sizeof(int64) }

// integers
const int Div1 = 7 / 2;
const int Div2 = -7 / 2;
const int Rem1 = -7 % 3;
const int Rem2 = 7 % -3;
const int Shl1 = 1 << 31;
const int Shl2 = 1 << 33;
const int Shr1 = -16 >> 2;
const uint32 Shr2 = 0x80000000u >> 31;
const int Not1 = ~5;
const int Mix = (5 & 3) | (8 ^ 1);
const int Min = -2147483648;
const int64 Big = 3000000000 * 2;
const uint64 Huge = 0xFFFFFFFFFFFFFFFFul / 2;
const int64 Neg64 = -9223372036854775807 - 1;
// promotion of small types
const uint8 Small = 200;
const int Promoted = Small + 100;
const int Sub = Small - 250;
const char Letter = 'a';
const int Code = Letter + 1;
const char Next = (char)(Letter + 1);
// floating point
const double Third = 1.0 / 3.0;
const float Third32 = 1.0f / 3.0f;
const double Mixed = 1 + 0.5f;
const double Rem = 7.5 % 2.0;
const int Trunc1 = (int)3.99;
const int Trunc2 = (int)-3.99;
const uint8 Sat1 = (uint8)300.5;
const int8 Sat2 = (int8)-1000.0;
const int NaN = (int)(0.0 / 0.0);
const double FromInt = (double)Big;
// conversions
const uint8 Wrapped = (uint8)300;
const int8 Wrapped2 = (int8)200;
const int64 Widened = K;
// bool
const bool And = true & false;
const bool Xor = true ^ true;
const bool Cmp = 3 < 4 && 2.5 >= 2.5 && 'a' < 'b';
const bool Lazy = false && (1 / 0 == 0);
const bool LazyOr = true || (1 / 0 == 0);
const bool Nan = 0.0 / 0.0 != 0.0 / 0.0;
// strings
const string Text = "a" + 1 + 2.5 + true + 'c' + Color.Green + 3.0f + (1.0 / 3.0);
const bool Same = "ab" + "c" == "abc";
// enums
const Color Fav = Color.Green;
const Color Made = (Color)6;
const Flags Rw = Flags.Read | Flags.Write;
const bool Order = Color.Red < Color.Blue && Fav == Color.Green;
const int Size = sizeof(int64) + sizeof(char);

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
    int seven = 7;
    int three = 3;
    int two = 2;
    int one = 1;
    int thirtyOne = 31;
    int thirtyThree = 33;
    int minus = -7;
    failed += Check("div", Div1 == seven / two && Div2 == minus / two && Div1 == 3 && Div2 == -3);
    failed += Check("rem", Rem1 == minus % three && Rem2 == seven % -three && Rem1 == -1 && Rem2 == 1);
    failed += Check("shl", Shl1 == one << thirtyOne && Shl1 == int.MinValue && Shl2 == one << thirtyThree && Shl2 == 2);
    int sixteen = -16;
    failed += Check("shr", Shr1 == sixteen >> two && Shr1 == -4);
    uint32 top = 0x80000000u;
    failed += Check("shr unsigned", Shr2 == top >> thirtyOne && Shr2 == 1u);
    failed += Check("not and mix", Not1 == ~(seven - 2) && Not1 == -6 && Mix == (((seven - 2) & three) | (8 ^ one)) && Mix == 9);
    failed += Check("min", Min == int.MinValue);
    failed += Check("64 bit", Big == (int64)3000000000 * 2 && Big == 6000000000 && Huge == 0xFFFFFFFFFFFFFFFFul / 2ul && Neg64 == int64.MinValue);

    uint8 small = 200;
    failed += Check("promoted", Promoted == small + 100 && Promoted == 300 && Sub == small - 250 && Sub == -50);
    char letter = 'a';
    failed += Check("char", Code == letter + 1 && Code == 98 && Next == (char)(letter + 1) && Next == 'b');

    double one3 = 1.0;
    double three3 = 3.0;
    float onef = 1.0f;
    float threef = 3.0f;
    failed += Check("double", Third == one3 / three3 && Third32 == onef / threef && Mixed == 1 + 0.5f && Rem == 7.5 % 2.0 && Rem == 1.5);
    double p = 3.99;
    double m = -3.99;
    double big = 300.5;
    double low = -1000.0;
    double zero = 0.0;
    failed += Check("float to int", Trunc1 == (int)p && Trunc1 == 3 && Trunc2 == (int)m && Trunc2 == -3);
    failed += Check("saturation", Sat1 == (uint8)big && Sat1 == 255 && Sat2 == (int8)low && Sat2 == -128 && NaN == (int)(zero / zero) && NaN == 0);
    int64 bigRuntime = 6000000000;
    failed += Check("int to double", FromInt == (double)bigRuntime);

    int three1 = 300;
    int twoH = 200;
    failed += Check("wrap", Wrapped == (uint8)three1 && Wrapped == 44 && Wrapped2 == (int8)twoH && Wrapped2 == -56 && Widened == 3);
    bool t = true;
    bool f = false;
    failed += Check("bool", And == (t & f) && Xor == (t ^ t) && !And && !Xor && Cmp && Lazy == false && LazyOr && Nan);
    string runtimeText = "a" + 1 + 2.5 + true + 'c' + Color.Green + 3.0f + (1.0 / 3.0);
    failed += Check("string", Text == runtimeText);
    failed += Check("string compare", Same);

    failed += Check("enum", Fav == Color.Green && Made == Color.Blue && Rw == Flags.Both && Order && (int)Made == 6);
    failed += Check("enum from constants", (int)FromConst.A == 6 && (int)FromConst.B == 7 && (int)FromConst.C == 9 && (int)FromConst.D == 8);
    failed += Check("flags", (int)Flags.Shifted == 8 && Flags.Both == (Flags)3);
    failed += Check("sizeof", Size == 9);
    if (failed == 0)
        Console.WriteLine("const_eval ok");
    return failed;
}
