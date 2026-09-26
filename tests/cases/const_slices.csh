// Constant slices: 'const ReadOnlySlice<T>' holds constant elements (numbers, bool, char, string, enums), written as a
// collection expression that may spread other constant slices. The elements live in static memory (nothing is
// allocated or freed); indexing, ^n, slicing and Length also work inside other constants. A thread function may read
// global constants.
// expect-exit: 0
// expect-stdout: 17 5 7 4 13
// expect-stdout: 2 3 5 7 11 13
// expect-stdout: Red,Green,Blue 5 true
// expect-stdout: local 3 30 2.5
// expect-stdout: thread 41
// expect-stdout: empty 0

using System;

enum Color : int32 { Red, Green, Blue }

const ReadOnlySlice<int> Primes = [2, 3, 5, 7];
const ReadOnlySlice<int> More = [..Primes, 11, 13];
const int Sum = Primes[0] + Primes[1] + Primes[2] + Primes[3];
const int Count = Primes.Length + 1;
const int Last = Primes[^1];
const int Middle = Primes[1..3].Length + More[2..][1] - 5;
const ReadOnlySlice<string> Names = ["Red", "Green", "Blue"];
const ReadOnlySlice<Color> Colors = [Color.Red, Color.Green, Color.Blue];
const ReadOnlySlice<int64> Wide = [1, 2, 3];
const ReadOnlySlice<int> None = [];
const int GreetingLength = "hello".Length;

string Join(ReadOnlySlice<string> parts)
{
    string text = "";
    foreach (var p in parts)
        text += (text.Length > 0 ? "," : "") + p;
    return text;
}

thread int SumPrimes(int extra)
{
    int total = extra;
    foreach (var p in More)
        total += p;
    return total;
}

int Main()
{
    Console.WriteLine(Sum.ToString() + " " + Count.ToString() + " " + Last.ToString() + " " + Middle.ToString() + " " +
                      More[^1].ToString());
    string all = "";
    foreach (var p in More)
        all += (all.Length > 0 ? " " : "") + p.ToString();
    Console.WriteLine(all);

    ReadOnlySlice<int> view = Primes;          // a view of the static block, no copy
    Console.WriteLine(Join(Names) + " " + GreetingLength.ToString() + " " + (Colors[2] == Color.Blue).ToString().ToLower());

    const ReadOnlySlice<double> Factors = [0.5, 1, 2.5];
    const int Local = Wide.Length;
    int[] copy = view.ToArray();
    copy[0] = 30;
    Console.WriteLine("local " + Local.ToString() + " " + copy[0].ToString() + " " + Factors[^1].ToString());

    var t = start SumPrimes(0);
    Console.WriteLine("thread " + t.Join().ToString());
    Console.WriteLine("empty " + None.Length.ToString());
    return 0;
}
