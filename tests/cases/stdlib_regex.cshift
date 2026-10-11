// Regex: groups (numbered and named), Replace with $n/${name}, Split, Matches, anchors, word boundaries, sets, lazy
// and counted repetition, (?i)/(?m), UTF-8 text, a pattern that would take exponential time in a plain backtracker,
// and the errors of invalid patterns.
// expect-stdout: 2026-10-01 2026 10 at 4, 3 groups
// expect-stdout: from 01.10.2026 to 31.01.2027
// expect-stdout: a|b|c
// expect-stdout: Hello@0 wide@7 world@12
// expect-stdout: true false
// expect-stdout: fast false
// expect-stdout: ignore case true
// expect-stdout: lazy <a> greedy <a><b>
// expect-stdout: set ab
// expect-stdout: utf8 äßö 6
// expect-stdout: lines 3
// expect-stdout: x # #x
// expect-stdout: -b--b-
// expect-stdout: optional group false ''
// expect-stdout: invalid regular expression '(abc' at 5: the group is not closed (')' is missing)
// expect-stdout: invalid regular expression 'a)' at 2: ')' without '('
// expect-stdout: invalid regular expression '*a' at 1: '*' has nothing to repeat
// expect-stdout: invalid regular expression '[a-' at 1: the set is not closed (']' is missing)
// expect-stdout: invalid regular expression 'a{3,1}' at 7: {n,m} with m < n
// expect-stdout: invalid regular expression '\1' at 2: backreferences (\1, ...) are not supported
// expect-stdout: invalid regular expression '\q' at 2: unknown escape '\q'
using System;

int Main()
{
    var re = try Regex.Create("(?<year>\\d{4})-(\\d{2})-(\\d{2})");
    if (re.Match("due 2026-10-01!") is RegexMatch m)
        Console.WriteLine(m.Value + " " + m.Group("year") + " " + m.Group(2) + " at " + m.Index.ToString() + ", " +
                          m.GroupCount().ToString() + " groups");
    Console.WriteLine(re.Replace("from 2026-10-01 to 2027-01-31", "$3.$2.${year}"));
    Console.WriteLine(string.Join("|", (try Regex.Create("\\s*,\\s*")).Split("a , b,c")));
    var words = List<string>.Create();
    foreach (var w in (try Regex.Create("\\b\\w+\\b")).Matches("Hello, wide world!"))
        words.Add(w.Value + "@" + w.Index.ToString());
    Console.WriteLine(string.Join(" ", words.ToArray()));
    var abc = try Regex.Create("^(a|b)*c$");
    Console.WriteLine(abc.IsMatch("ababc").ToString() + " " + abc.IsMatch("abxc").ToString());
    Console.WriteLine("fast " + (try Regex.Create("(a*)*b")).IsMatch("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaac").ToString());
    Console.WriteLine("ignore case " + (try Regex.Create("(?i)hello")).IsMatch("Say HeLLo").ToString());
    string lazy = (try Regex.Create("<.+?>")).Match("<a><b>") is RegexMatch l ? l.Value : "none";
    string greedy = (try Regex.Create("<.+>")).Match("<a><b>") is RegexMatch g ? g.Value : "none";
    Console.WriteLine("lazy " + lazy + " greedy " + greedy);
    Console.WriteLine("set " + ((try Regex.Create("[^\\d\\s]+")).Match("12 ab3") is RegexMatch s ? s.Value : "none"));
    Console.WriteLine("utf8 " + ((try Regex.Create("ä.ö")).Match("xäßöy") is RegexMatch u ? u.Value + " " + u.Length.ToString() : "none"));
    Console.WriteLine("lines " + (try Regex.Create("(?m)^\\w+$")).Matches("one\ntwo\nthree").Length.ToString());
    Console.WriteLine((try Regex.Create("x{2,3}")).Replace("x xx xxxx", "#"));
    Console.WriteLine((try Regex.Create("a|")).Replace("bab", "-"));
    if ((try Regex.Create("b(x)?c")).Match("abc") is RegexMatch o)
        Console.WriteLine("optional group " + o.GroupMatched(1).ToString() + " '" + o.Group(1) + "'");
    string[] bad = ["(abc", "a)", "*a", "[a-", "a{3,1}", "\\1", "\\q"];
    foreach (var b in bad)
    {
        if (Regex.Create(b) is error e)
            Console.WriteLine(e.Message);
    }
    return 0;
}
