// An enum as text (concatenation, interpolation, ToString(), constants) is the name of its member, like C#; a value
// that is no member gives its number, and members that share a value print the first name.
// expect-exit: 0
// expect-stdout: color Green Blue Red 9 Green
// expect-stdout: Neg Huge 4
// expect-stdout: Parse 7
// expect-stdout: const Blue

using System;

enum Color : uint8 { Red, Green = 5, Blue, Lime = 5 }
enum Big : int64 { Neg = -3, Huge = 9000000000 }
error Fail { Io, Parse = 7 }

const string Constant = "const " + Color.Blue;

int Main()
{
    Color c = Color.Green;
    Console.WriteLine("color " + c + " " + Color.Blue.ToString() + " " + $"{Color.Red}" + " " + (Color)9 + " " + Color.Lime);
    Console.WriteLine($"{Big.Neg} {Big.Huge} {(Big)4}");
    Console.WriteLine($"{Fail.Parse} {(int)Fail.Parse}");
    Console.WriteLine(Constant);
    return 0;
}
