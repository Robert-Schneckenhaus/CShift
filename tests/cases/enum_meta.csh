// Enum<T> gives facts about an enum as constants: Count (the number of members), Min and Max (the smallest and largest
// value, of the enum's type), Values and Names (constant slices, in declaration order). It works in constants, at run
// time, in generic functions and for error enums.
// expect-exit: 0
// expect-stdout: 3 Red Blue 0 2
// expect-stdout: Low High -5 200 4
// expect-stdout: Red=0 Green=1 Blue=2
// expect-stdout: generic 3 4
// expect-stdout: errors 2 NotFound Denied
// expect-stdout: const 3 Blue 8

using System;

enum Color : int32 { Red, Green, Blue }
enum Level : int16 { Mid = 7, Low = -5, High = 200, Other = 7 }
enum Flags : uint8 { A = 1, B = 128 }
error FileError { NotFound, Denied }

const int ColorCount = Enum<Color>.Count;
const Color LastColor = Enum<Color>.Max;
const ReadOnlySlice<Color> AllColors = Enum<Color>.Values;
const int Total = (int)Enum<Color>.Max + Enum<Color>.Values.Length + Enum<Color>.Names[0].Length;

int CountOf<T>()
{
    return Enum<T>.Count;
}

int Main()
{
    Console.WriteLine(Enum<Color>.Count.ToString() + " " + Enum<Color>.Min.ToString() + " " + Enum<Color>.Max.ToString() + " " +
                      ((int)Enum<Color>.Min).ToString() + " " + ((int)Enum<Color>.Max).ToString());
    Console.WriteLine(Enum<Level>.Min.ToString() + " " + Enum<Level>.Max.ToString() + " " + ((int)Enum<Level>.Min).ToString() + " " +
                      ((int)Enum<Level>.Max).ToString() + " " + Enum<Level>.Count.ToString());
    string text = "";
    for (var i = 0; i < Enum<Color>.Count; i += 1)
        text += (i > 0 ? " " : "") + Enum<Color>.Names[i] + "=" + ((int)Enum<Color>.Values[i]).ToString();
    Console.WriteLine(text);
    Console.WriteLine("generic " + CountOf<Color>().ToString() + " " + CountOf<Level>().ToString());
    Console.WriteLine("errors " + Enum<FileError>.Count.ToString() + " " + Enum<FileError>.Min.ToString() + " " +
                      Enum<FileError>.Names[1]);
    Console.WriteLine("const " + ColorCount.ToString() + " " + LastColor.ToString() + " " + Total.ToString());
    if (Enum<Flags>.Max != Flags.B || AllColors.Length != 3)
        return 1;
    return 0;
}
