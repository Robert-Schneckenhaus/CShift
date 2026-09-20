// Exercises reference counting on many code paths. The test runner checks that every heap
// block was freed again ([arc] live=0) and that Main returns 0 (no failed check).
// expect-exit: 0

struct Item
{
    string Name;
    int[] Values;
}

struct Holder
{
    Item First;
    Item Second;
    string Label;
}

Item MakeItem(int i)
{
    return Item { Name = "item" + i, Values = new int[i + 1] };
}

string Longest(string[] names)
{
    string best = "";
    foreach (var n in names)
    {
        if (n.Length > best.Length)
            best = n;
    }
    return best;
}

string PassThrough(string s)
{
    return s;
}

string Reassign(string s)
{
    s = s + "!";
    s = s + "?";
    return s;
}

Error<string> Load(int i)
{
    if (i % 4 == 3)
        return error("bad " + i);
    return "ok" + i;
}

Error<int> Process(int n)
{
    int count = 0;
    for (var i = 0; i < n; i += 1)
    {
        var s = try Load(i);
        string local = s + s;
        count += local.Length;
    }
    return count;
}

Optional<string> Maybe(int i)
{
    if (i % 2 == 0)
        return "even" + i;
    return null;
}

string FirstEven(int limit)
{
    for (var i = 1; i < limit; i += 1)
    {
        if (Maybe(i) is string s)
            return s;
    }
    return "none";
}

int Score(string cmd)
{
    switch (cmd + "x")
    {
        case "addx":
            return 1;
        case "subx":
            return 2;
        default:
            return 0;
    }
}

Holder Combine(Item a, Item b)
{
    return Holder { First = a, Second = b, Label = a.Name + "+" + b.Name };
}

int Main()
{
    int failures = 0;

    // strings in loops
    string acc = "";
    for (var i = 0; i < 200; i += 1)
    {
        acc += i;
        if (acc.Length > 50)
            acc = "";
    }
    if (acc.Length > 50)
        failures += 1;

    // structs with ARC fields, copies and reassignment
    var items = new Item[10];
    for (var i = 0; i < items.Length; i += 1)
        items[i] = MakeItem(i);
    var copy = items.Clone();
    items[0] = MakeItem(99);
    if (copy[0].Name != "item0" || items[0].Name != "item99")
        failures += 1;
    var h = Combine(items[1], copy[2]);
    if (h.Label != "item1+item2")
        failures += 1;
    var h2 = h;
    h2.First = MakeItem(5);
    if (h.First.Name != "item1" || h2.First.Name != "item5")
        failures += 1;

    // string arrays
    var names = new string[] { "a", "bbb", "cc" };
    if (Longest(names) != "bbb")
        failures += 1;
    if (PassThrough(names[1] + "z") != "bbbz" || Reassign("q") != "q!?")
        failures += 1;

    // try in loops with early exit
    var okResult = Process(3);
    if (okResult is int total)
    {
        if (total != 2 * ("ok0".Length + "ok1".Length + "ok2".Length))
            failures += 1;
    }
    else
        failures += 1;
    var badResult = Process(10);
    if (badResult || badResult.Message != "bad 3")
        failures += 1;

    // Optional with pattern variables in loops
    if (FirstEven(10) != "even2" || FirstEven(2) != "none")
        failures += 1;
    string joined = "";
    for (var i = 0; i < 10; i += 1)
    {
        if (Maybe(i) is string s)
            joined += s;
    }
    if (joined != "even0even2even4even6even8")
        failures += 1;
    int k = 0;
    while (Maybe(k) is string w)
    {
        k += 2;
        if (k > 6)
            break;
    }

    // switch on temporary strings
    if (Score("add") != 1 || Score("sub") != 2 || Score("mul") != 0)
        failures += 1;

    // conditional expression with owned and borrowed branches
    string pick = failures == 0 ? "a" + "b" : names[0];
    if (pick != "ab")
        failures += 1;

    // break / continue inside foreach with an ARC loop variable
    int seen = 0;
    foreach (var n in names)
    {
        if (n == "bbb")
            continue;
        var tmp = n + n;
        if (tmp == "cccc")
            break;
        seen += 1;
    }
    if (seen != 1)
        failures += 1;

    return failures;
}
