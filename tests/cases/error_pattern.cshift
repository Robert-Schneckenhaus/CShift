// 'is error e' matches a failed Error<T> and binds the whole result (e.Message, e.Code): for every Error<T>
// (Error<int>, Error<void>, Error<Optional<T>>), also in a switch.
// expect-exit: 0
// expect-stdout: error negative key 7
// expect-stdout: switch: negative key
// expect-stdout: nothing found
// expect-stdout: value 1
// expect-stdout: parse failed: empty (1)
// expect-stdout: parsed 3
// expect-stdout: switch parsed 3
// expect-stdout: switch parse failed: empty
// expect-stdout: save failed: disk full
// expect-stdout: saved

using System;
Error<Optional<int>> Find(int k) { if (k < 0) return error("negative key", 7); if (k == 0) return null; return k; }
Error<int> Parse(string text) { if (text.Length == 0) return error("empty", 1); return text.Length; }
Error<void> Save(bool ok) { if (!ok) return error("disk full"); return; }

int Main()
{
    for (var k = -1; k <= 1; k += 1)
    {
        var r = Find(k);
        if (r is error e)
            Console.WriteLine($"error {e.Message} {e.Code}");
        else if (r is int v)
            Console.WriteLine($"value {v}");
        else
            Console.WriteLine("nothing found");
        switch (r)
        {
            case error failure:
                Console.WriteLine("switch: " + failure.Message);
                break;
            case Optional<int> o:
                Console.WriteLine("switch: ok");
                break;
        }
    }

    if (Parse("") is error pe)
        Console.WriteLine($"parse failed: {pe.Message} ({pe.Code})");
    if (!(Parse("abc") is error) && Parse("abc") is int n)
        Console.WriteLine($"parsed {n}");
    foreach (var text in new string[] { "abc", "" })
    {
        switch (Parse(text))
        {
            case int parsed:
                Console.WriteLine($"switch parsed {parsed}");
                break;
            case error failure:
                Console.WriteLine("switch parse failed: " + failure.Message);
                break;
        }
    }
    foreach (var ok in new bool[] { false, true })
    {
        if (Save(ok) is error se)
            Console.WriteLine("save failed: " + se.Message);
        else
            Console.WriteLine("saved");
    }
    return 0;
}
