// Array.Copy (also for overlapping ranges and ARC elements), string.FromBytes and foreach over structs
// that provide Count() and Get(int). Main returns the number of failed checks.
// expect-exit: 0

struct Range
{
    int From;
    int To;

    int Count()
    {
        return To - From;
    }

    int Get(int index)
    {
        return From + index;
    }
}

struct Names
{
    string[] Items;

    int Count()
    {
        return Items.Length;
    }

    string Get(int index)
    {
        return Items[index] + "!";
    }
}

struct Item
{
    string Name;
    int[] Values;
}

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

string Show(int[] a)
{
    string s = "";
    foreach (var v in a)
        s += v + ",";
    return s;
}

string ShowNames(string[] a)
{
    string s = "";
    foreach (var v in a)
        s += v + ",";
    return s;
}

int Main()
{
    int f = 0;

    // ---- Array.Copy with plain elements ----
    var a = new int[] { 1, 2, 3, 4, 5 };
    Array.Copy(a, 0, a, 1, 4);
    f += Check("copy overlapping to the right", Show(a) == "1,1,2,3,4,");
    var b = new int[] { 1, 2, 3, 4, 5 };
    Array.Copy(b, 1, b, 0, 4);
    f += Check("copy overlapping to the left", Show(b) == "2,3,4,5,5,");
    var c = new int[5];
    Array.Copy(b, c, 3);
    f += Check("copy short form", Show(c) == "2,3,4,0,0,");
    Array.Copy(a, 5, a, 5, 0);
    f += Check("copy nothing at the end", Show(a) == "1,1,2,3,4,");

    // ---- Array.Copy with ARC elements (strings) ----
    var s = new string[] { "a", "b", "c", "d" };
    Array.Copy(s, 0, s, 1, 3);
    f += Check("string copy to the right", ShowNames(s) == "a,a,b,c,");
    var t = new string[] { "a", "b", "c", "d" };
    Array.Copy(t, 1, t, 0, 3);
    f += Check("string copy to the left", ShowNames(t) == "b,c,d,d,");
    var u = new string[4];
    Array.Copy(t, u, 4);
    t[0] = "changed";
    f += Check("string copy between arrays", ShowNames(u) == "b,c,d,d," && t[0] == "changed");

    // ---- Array.Copy with structs that contain ARC members ----
    var items = new Item[3];
    for (var i = 0; i < items.Length; i += 1)
        items[i] = Item { Name = "item" + i, Values = new int[i] };
    var moved = new Item[4];
    Array.Copy(items, 0, moved, 1, 3);
    Array.Copy(moved, 1, moved, 0, 3);
    f += Check("struct copy", moved[0].Name == "item0" && moved[2].Name == "item2" && moved[2].Values.Length == 2 &&
                              moved[3].Name == "item2" && moved[3].Values.Length == 2);

    // ---- string.FromBytes ----
    f += Check("FromBytes", string.FromBytes(new uint8[] { 72, 105 }) == "Hi" && string.FromBytes(new uint8[0]) == "");

    // ---- foreach over structs ----
    var range = Range { From = 3, To = 8 };
    int sum = 0;
    foreach (var n in range)
        sum += n;
    f += Check("foreach struct", sum == 3 + 4 + 5 + 6 + 7);

    int64 wide = 0;
    foreach (int64 n in range)
    {
        if (n == 4)
            continue;
        if (n == 7)
            break;
        wide += n;
    }
    f += Check("foreach struct with declared type, continue and break", wide == 3 + 5 + 6);

    var names = Names { Items = new string[] { "x", "y" } };
    string joined = "";
    foreach (var name in names)
        joined += name;
    f += Check("foreach struct with strings", joined == "x!y!");

    int nested = 0;
    foreach (var outer in Range { From = 0, To = 3 })
    {
        foreach (var inner in Range { From = 0, To = outer })
            nested += 1;
    }
    f += Check("nested foreach over temporaries", nested == 0 + 1 + 2);

    return f;
}
