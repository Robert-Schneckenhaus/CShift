// Standard library: paths, directories, File.Copy, string trimming/padding and Random. The program runs in a
// temporary directory. Main returns the number of failed checks.
// expect-exit: 0

using System;

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

int Main()
{
    int failed = 0;

    // strings
    failed += Check("TrimStart", "  a b ".TrimStart() == "a b ");
    failed += Check("TrimEnd", "  a b \n".TrimEnd() == "  a b");
    failed += Check("TrimStart char", "007".TrimStart('0') == "7");
    failed += Check("TrimEnd char", "1.500".TrimEnd('0') == "1.5");
    failed += Check("PadLeft", "7".PadLeft(3) == "  7");
    failed += Check("PadLeft fill", "7".PadLeft(3, '0') == "007");
    failed += Check("PadLeft long", "1234".PadLeft(2) == "1234");
    failed += Check("PadRight", "ab".PadRight(4, '.') == "ab..");
    failed += Check("IndexOf char start", "a,b,c".IndexOf(',', 2) == 3);
    failed += Check("IndexOf char none", "a,b,c".IndexOf(',', 4) == -1);

    // paths and directories
    string cwd = Directory.GetCurrentDirectory();
    failed += Check("current directory", cwd.Length > 0 && Directory.Exists(cwd));
    failed += Check("full path", Path.GetFullPath("a/./b/../c.txt") == Path.GetFullPath(".") + "/a/c.txt");
    failed += Check("full path rooted", Path.GetFullPath("/x/y/../z") == "/x/z" || Path.GetFullPath("/x/y/../z").EndsWith(":/x/z"));
    failed += Check("relative path", Path.GetRelativePath("/a/b/c", "/a/d/e.txt") == "../../d/e.txt");
    failed += Check("relative path same", Path.GetRelativePath("/a/b", "/a/b") == ".");
    failed += Check("relative path below", Path.GetRelativePath("/a", "/a/b/c") == "b/c");
    failed += Check("create nested", Directory.Create("d1/d2/d3") && Directory.Exists("d1/d2/d3"));
    failed += Check("write", File.WriteAllText("d1/d2/one.txt", "hello") is Error<void> w && w);
    failed += Check("copy", File.Copy("d1/d2/one.txt", "d1/two.txt") is Error<void> c && c);
    failed += Check("copied", File.ReadAllText("d1/two.txt") is string text && text == "hello");
    failed += Check("copy no overwrite", !File.Copy("d1/d2/one.txt", "d1/two.txt"));
    failed += Check("copy overwrite", File.Copy("d1/d2/one.txt", "d1/two.txt", true) is Error<void> o && o);
    var entries = Directory.GetEntries("d1");
    failed += Check("entries", entries.Count() == 2 && entries.Get(0) == "d2" && entries.Get(1) == "two.txt");
    failed += Check("find files", Directory.FindFiles("d1", ".txt").Count() == 2);
    failed += Check("not a directory", !Directory.Exists("d1/two.txt"));

    // Random: the same seed gives the same sequence
    var r1 = Random.Create(42);
    var r2 = Random.Create(42);
    bool same = true;
    bool inRange = true;
    for (var i = 0; i < 1000; i += 1)
    {
        int a = r1.Next(1, 7);
        same = same && a == r2.Next(1, 7);
        inRange = inRange && a >= 1 && a <= 6;
        double d = r1.NextDouble();
        r2.NextDouble();
        inRange = inRange && d >= 0.0 && d < 1.0;
    }
    failed += Check("random repeatable", same);
    failed += Check("random range", inRange);
    var r3 = Random.Create(43);
    failed += Check("random seeds differ", Random.Create(42).Next() != r3.Next());
    return failed;
}
