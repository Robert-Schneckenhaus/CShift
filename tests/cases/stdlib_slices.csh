// The string helpers work on StringSlice: Trim and Split return views (nothing is copied), queries and parsers take
// slices (a string converts for free), and the helpers can be called on a slice like on a string.
// expect-exit: 0
// expect-stdout: [a b] [c] 3
// expect-stdout: key=name value=Ann Lee
// expect-stdout: 42 true false 1 ANN
// expect-stdout: a|b|c 1.5
// expect-stdout: x=y;y=z

using System;

int Main()
{
    string line = "  a b ,c , ";
    StringSlice[] parts = line.Split(',');
    Console.WriteLine($"[{parts[0].Trim()}] [{parts[1].Trim()}] {parts.Length}");

    string entry = "name = Ann Lee";
    int eq = entry.IndexOf('=');
    StringSlice key = entry[..eq].Trim();
    StringSlice value = entry[eq + 1..].Trim();
    Console.WriteLine("key=" + key + " value=" + value);

    string numbers = "x42y";
    int n = 0;
    if (numbers[1..3].ParseInt() is int parsed)
        n = parsed;
    Console.WriteLine($"{n} {value.StartsWith("Ann")} {value.Contains("Bob")} {value.IndexOf('n')} {value[..3].ToUpper()}");

    double d = 0;
    if ("v=1.5"[2..].ParseDouble() is double parsedDouble)
        d = parsedDouble;
    Console.WriteLine(string.Join("|", "a,b,c".Split(',')) + " " + d);
    var sb = StringBuilder.Create();
    string config = "x=y;y=z;";
    sb.Append(config[..^1]);
    Console.WriteLine(sb.ToString());
    return 0;
}
