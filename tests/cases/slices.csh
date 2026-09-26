// Slices: a[i..j], a[..j], a[i..], a[..] and ^n (from the end) give views - Slice<T> of arrays, StringSlice of strings -
// without copying. A view keeps its array or string alive, writes through a Slice<T> change the array, ToString() /
// ToArray() copy explicitly. Slices work with foreach, ==, text, generics, struct fields and List<T>.
// expect-exit: 0
// expect-stdout: 3 2 4 9 21 2
// expect-stdout: 20 6 15 39 7
// expect-stdout: world|hello|rld|bravo
// expect-stdout: true true true 5 w
// expect-stdout: world 3 99 20
// expect-stdout: bob cid
// expect-stdout: [] 0 0
// expect-stdout: fields ab cd 2

using System;

int Sum(Slice<int> values)
{
    int total = 0;
    foreach (var v in values)
        total += v;
    return total;
}

T Last<T>(Slice<T> items)
{
    return items[^1];
}

StringSlice Word(string text, int n)
{
    return text[n * 6..n * 6 + 5];
}

int Main()
{
    int[] a = new int[] { 1, 2, 3, 4, 5, 6 };
    Slice<int> mid = a[1..4];
    Console.WriteLine($"{mid.Length} {mid[0]} {mid[^1]} {Sum(mid)} {Sum(a)} {Last(a[..2])}");
    mid[0] = 20;                         // writes through to the array
    Console.WriteLine($"{a[1]} {a[^1]} {Sum(a[3..])} {Sum(a[..])} {Sum(mid[1..])}");

    string s = "hello world";
    StringSlice w = s[6..];
    Console.WriteLine(w + "|" + s[..5] + "|" + s[^3..] + "|" + Word("alpha bravo", 1));
    Console.WriteLine($"{w == "world"} {s[0..5] == s[..5]} {w != "word"} {w.Length} {w[0]}");
    string copy = w.ToString();
    int[] copied = mid.ToArray();
    copied[0] = 99;
    Console.WriteLine($"{copy} {copied.Length} {copied[0]} {a[1]}");

    string[] names = new string[] { "ann", "bob", "cid" };
    Slice<string> some = names[1..];
    names = null;                        // the slice keeps the array (and its strings) alive
    foreach (var n in some)
        Console.Write(n + " ");
    Console.WriteLine();

    StringSlice empty = null;
    Console.WriteLine($"[{empty}] {empty.Length} {s[3..3].Length}");
    Fields();
    return 0;
}

struct Token
{
    StringSlice Text;
    int Line;
}

void Fields()
{
    string source = "ab cd";
    var tokens = List<Token>.Create();
    tokens.Add(Token { Text = source[..2], Line = 1 });
    tokens.Add(Token { Text = source[3..], Line = 2 });
    source = "";                         // the tokens still see the old text
    Console.WriteLine("fields " + tokens[0].Text + " " + tokens[1].Text + " " + tokens[1].Line);
}
