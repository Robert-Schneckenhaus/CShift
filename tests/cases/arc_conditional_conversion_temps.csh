// A branch of a conditional whose value is converted (an array to a slice, a string to a StringSlice) releases the
// temporaries of the conversion in that branch: they do not exist in the other one (the IR was invalid before).
// expect-stdout: 2 0 plain
// expect-stdout: 0 0 n1!
// expect-stdout: 2 1 plain
// expect-stdout: 0 0 plain

string Name(int i)
{
    return "n" + i.ToString();
}

int Main()
{
    string[] none = new string[0];
    for (var i = 0; i < 4; i += 1)
    {
        ReadOnlySlice<string> a = i % 2 == 0 ? new string[] { Name(i), "x" } : none[0..];
        ReadOnlySlice<string> b = i < 2 ? none[0..] : (i == 2 ? new string[] { Name(i) } : new string[0]);
        StringSlice s = i == 1 ? Name(i) + "!" : "plain";
        Console.WriteLine($"{a.Length} {b.Length} {s}");
    }
    return 0;
}
