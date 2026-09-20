// Standard library: Dictionary<TKey, TValue>. Main returns the number of failed checks.
// expect-exit: 0

using System;

enum Color : uint8
{
    Red,
    Green,
    Blue
}

struct Point : IEquatable<Point>, IHashable
{
    int X;
    int Y;

    bool Equals(Point other)
    {
        return X == other.X && Y == other.Y;
    }

    int GetHashCode()
    {
        return X * 31 + Y;
    }
}

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

bool Succeeded(Error<void> result)
{
    if (result)
        return true;
    return false;
}

int Main()
{
    int f = 0;

    // ---- basics ----
    var ages = Dictionary<string, int>.Create();
    f += Check("empty", ages.Count() == 0 && !ages.ContainsKey("Ann"));
    ages.Set("Ann", 31);
    ages.Set("Bob", 25);
    ages.Set("Cid", 40);
    f += Check("count", ages.Count() == 3);
    if (ages.TryGet("Bob") is int bob)
        f += Check("TryGet", bob == 25);
    else
        f += 1;
    f += Check("TryGet missing", !ages.TryGet("Zed") && ages.TryGet("Zed") == null);
    f += Check("ContainsKey", ages.ContainsKey("Ann") && !ages.ContainsKey("ann"));
    ages.Set("Bob", 26);
    f += Check("Set replaces", ages.Count() == 3 && ages.GetOrDefault("Bob", -1) == 26);
    f += Check("GetOrDefault", ages.GetOrDefault("Nobody", -1) == -1 && ages.GetOrDefault("Ann", -1) == 31);

    // ---- Add fails for existing keys ----
    var duplicate = ages.Add("Ann", 1);
    f += Check("Add duplicate", !duplicate && duplicate.Message.Contains("same key") && ages.GetOrDefault("Ann", -1) == 31);
    f += Check("Add new", Succeeded(ages.Add("Dan", 5)) && ages.Count() == 4);

    // ---- Remove and slot reuse ----
    f += Check("Remove", ages.Remove("Ann") && ages.Count() == 3 && !ages.ContainsKey("Ann"));
    f += Check("Remove missing", !ages.Remove("Ann") && !ages.Remove("nobody"));
    ages.Set("Eve", 22);
    f += Check("reuse slot", ages.Count() == 4 && ages.GetOrDefault("Eve", -1) == 22 && ages.GetOrDefault("Cid", -1) == 40);

    // ---- Keys / Values / Entries ----
    var keys = ages.Keys();
    var values = ages.Values();
    int keyLength = 0;
    foreach (var k in keys)
        keyLength += k.Length;
    int valueSum = 0;
    foreach (var v in values)
        valueSum += v;
    f += Check("Keys/Values", keys.Length == 4 && values.Length == 4 && keyLength == 12 && valueSum == 26 + 40 + 5 + 22);
    int entrySum = 0;
    foreach (var entry in ages.Entries())
        entrySum += entry.Key.Length * entry.Value;
    f += Check("Entries", entrySum == 3 * (26 + 40 + 5 + 22));

    // ---- Clear ----
    ages.Clear();
    f += Check("Clear", ages.Count() == 0 && !ages.ContainsKey("Bob") && ages.Keys().Length == 0);
    ages.Set("again", 1);
    f += Check("Set after Clear", ages.Count() == 1);

    // ---- many entries (resizing) ----
    var squares = Dictionary<int, int>.Create();
    for (var i = 0; i < 2000; i += 1)
        squares.Set(i, i * i);
    bool allFound = squares.Count() == 2000;
    for (var i = 0; i < 2000; i += 1)
        allFound = allFound && squares.GetOrDefault(i, -1) == i * i;
    f += Check("2000 entries", allFound);
    for (var i = 0; i < 2000; i += 2)
        squares.Remove(i);
    bool oddsLeft = squares.Count() == 1000;
    for (var i = 0; i < 2000; i += 1)
        oddsLeft = oddsLeft && (squares.ContainsKey(i) == (i % 2 == 1));
    f += Check("remove evens", oddsLeft);
    for (var i = 0; i < 2000; i += 2)
        squares.Set(i, -i);
    f += Check("re-add", squares.Count() == 2000 && squares.GetOrDefault(10, 0) == -10 && squares.GetOrDefault(11, 0) == 121);

    // ---- other key types ----
    var byPoint = Dictionary<Point, string>.Create();
    byPoint.Set(Point { X = 1, Y = 2 }, "a");
    byPoint.Set(Point { X = 2, Y = 1 }, "b");
    byPoint.Set(Point { X = 1, Y = 2 }, "c");
    f += Check("struct keys", byPoint.Count() == 2 && byPoint.GetOrDefault(Point { X = 1, Y = 2 }, "?") == "c" &&
                              byPoint.GetOrDefault(Point { X = 2, Y = 1 }, "?") == "b" &&
                              !byPoint.ContainsKey(Point { X = 3, Y = 3 }));

    var byColor = Dictionary<Color, int>.Create();
    byColor.Set(Color.Red, 1);
    byColor.Set(Color.Blue, 3);
    f += Check("enum keys", byColor.Count() == 2 && byColor.GetOrDefault(Color.Blue, 0) == 3 && !byColor.ContainsKey(Color.Green));

    var byLong = Dictionary<int64, bool>.Create();
    byLong.Set(5000000000, true);
    byLong.Set(-1, false);
    f += Check("int64 keys", byLong.GetOrDefault(5000000000, false) && !byLong.GetOrDefault(-1, true) && byLong.Count() == 2);

    var byChar = Dictionary<char, int>.Create();
    foreach (var c in "hello world")
        byChar.Set(c, byChar.GetOrDefault(c, 0) + 1);
    f += Check("char keys (letter counts)", byChar.GetOrDefault('l', 0) == 3 && byChar.GetOrDefault('o', 0) == 2 && byChar.Count() == 8);

    // ---- values with ARC, nested containers ----
    var groups = Dictionary<string, List<int>>.Create();
    for (var i = 0; i < 10; i += 1)
    {
        string key = i % 2 == 0 ? "even" : "odd";
        if (!groups.ContainsKey(key))
            groups.Set(key, List<int>.Create());
        groups.GetOrDefault(key, List<int>.Create()).Add(i);
    }
    f += Check("dictionary of lists", groups.Count() == 2 && groups.GetOrDefault("even", List<int>.Create()).Count() == 5);
    if (groups.TryGet("odd") is List<int> odd)
        f += Check("TryGet list", odd.Count() == 5 && odd.Get(0) == 1);
    else
        f += 1;

    // ---- a dictionary that was never created explicitly ----
    var lazy = new Dictionary<string, string>();
    f += Check("lazy empty", lazy.Count() == 0 && !lazy.ContainsKey("a") && !lazy.Remove("a") && lazy.Keys().Length == 0);
    lazy.Set("k", "v");
    f += Check("lazy Set", lazy.Count() == 1 && lazy.GetOrDefault("k", "") == "v");

    return f;
}
