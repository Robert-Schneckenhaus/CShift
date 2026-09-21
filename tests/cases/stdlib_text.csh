// Standard library: Char, StringBuilder, HashSet. Main returns the number of failed checks.
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

    // Char
    failed += Check("IsDigit", Char.IsDigit('7') && !Char.IsDigit('a'));
    failed += Check("IsLetter", Char.IsLetter('q') && Char.IsLetter('Q') && !Char.IsLetter('_'));
    failed += Check("IsLetterOrDigit", Char.IsLetterOrDigit('9') && Char.IsLetterOrDigit('z') && !Char.IsLetterOrDigit('-'));
    failed += Check("IsHexDigit", Char.IsHexDigit('F') && Char.IsHexDigit('c') && !Char.IsHexDigit('g'));
    failed += Check("IsWhiteSpace", Char.IsWhiteSpace(' ') && Char.IsWhiteSpace('\n') && !Char.IsWhiteSpace('x'));
    failed += Check("ToUpper", Char.ToUpper('a') == 'A' && Char.ToUpper('Z') == 'Z' && Char.ToUpper('1') == '1');
    failed += Check("ToLower", Char.ToLower('A') == 'a' && Char.ToLower('z') == 'z');
    failed += Check("HexValue", Char.HexValue('f') == 15 && Char.HexValue('7') == 7 && Char.HexValue('x') == -1);

    // StringBuilder
    var sb = StringBuilder.Create();
    failed += Check("empty", sb.Length() == 0 && sb.ToString() == "");
    sb.Append("hello");
    sb.Append(' ');
    sb.Append("world");
    failed += Check("append", sb.ToString() == "hello world" && sb.Length() == 11);
    sb.AppendLine("!");
    failed += Check("appendline", sb.ToString() == "hello world!\n");
    failed += Check("get", sb.Get(1) == 'e');
    sb.Clear();
    failed += Check("clear", sb.Length() == 0 && sb.ToString() == "");

    var big = StringBuilder.Create(4);
    for (var i = 0; i < 1000; i += 1)
        big.Append("ab");
    string bigText = big.ToString();
    failed += Check("grow", bigText.Length == 2000 && bigText[0] == 'a' && bigText[1999] == 'b');

    var utf = StringBuilder.Create();
    utf.Append("héllo");
    failed += Check("utf8", utf.ToString() == "héllo" && utf.Length() == 6);

    var shared = StringBuilder.Create();
    var alias = shared;
    alias.Append("x");
    failed += Check("shared storage", shared.ToString() == "x");

    var lazy = new StringBuilder();
    lazy.Append("lazy");
    failed += Check("new StringBuilder", lazy.ToString() == "lazy");

    // HashSet
    var set = HashSet<string>.Create();
    failed += Check("set add", set.Add("a") && set.Add("b") && !set.Add("a"));
    failed += Check("set count", set.Count() == 2);
    failed += Check("set contains", set.Contains("a") && !set.Contains("c"));
    failed += Check("set remove", set.Remove("a") && !set.Contains("a") && !set.Remove("a"));
    failed += Check("set toarray", set.ToArray().Length == 1);
    var numbers = HashSet<int>.Create();
    for (var i = 0; i < 100; i += 1)
        numbers.Add(i % 10);
    failed += Check("set ints", numbers.Count() == 10);

    return failed;
}
