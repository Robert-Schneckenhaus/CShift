// Standard library: List<T>. Main returns the number of failed checks.
// expect-exit: 0

using System;

struct Version : IComparable<Version>, IEquatable<Version>
{
    int Major;
    int Minor;

    int CompareTo(Version other)
    {
        if (Major != other.Major)
            return Major.CompareTo(other.Major);
        return Minor.CompareTo(other.Minor);
    }

    bool Equals(Version other)
    {
        return Major == other.Major && Minor == other.Minor;
    }
}

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

string Join(List<string> items)
{
    string result = "";
    foreach (var item in items)
    {
        if (result.Length > 0)
            result += ",";
        result += item;
    }
    return result;
}

void Fill(List<int> list)
{
    for (var i = 0; i < 5; i += 1)
        list.Add(i);
}

bool IsSorted(List<int> list)
{
    for (var i = 1; i < list.Count(); i += 1)
    {
        if (list.Get(i - 1) > list.Get(i))
            return false;
    }
    return true;
}

int Main()
{
    int f = 0;

    // ---- basics ----
    var list = List<int>.Create();
    f += Check("empty", list.Count() == 0);
    for (var i = 0; i < 100; i += 1)
        list.Add(i * 2);
    f += Check("count", list.Count() == 100 && list.Capacity() >= 100);
    f += Check("get", list.Get(0) == 0 && list.Get(99) == 198);
    list.Set(5, -1);
    f += Check("set", list.Get(5) == -1);
    int sum = 0;
    foreach (var v in list)
        sum += v;
    f += Check("foreach", sum == 9900 - 10 - 1);

    // ---- a list that was never created explicitly works as well ----
    var lazy = new List<int>();
    f += Check("lazy empty", lazy.Count() == 0 && lazy.Capacity() == 0 && !lazy.Contains(1));
    lazy.Add(7);
    lazy.Add(8);
    f += Check("lazy add", lazy.Count() == 2 && lazy.Get(1) == 8);

    // ---- copies share the elements ----
    var shared = List<int>.Create();
    Fill(shared);
    var alias = shared;
    alias.Add(99);
    f += Check("shared storage", shared.Count() == 6 && shared.Get(5) == 99);
    var withCapacity = List<int>.Create(50);
    f += Check("Create(capacity)", withCapacity.Count() == 0 && withCapacity.Capacity() >= 50);

    // ---- insert / remove (strings: ARC elements) ----
    var names = List<string>.Create();
    names.Add("a");
    names.Add("b");
    names.Add("d");
    names.Insert(2, "c");
    names.Insert(0, "start");
    names.Insert(names.Count(), "end");
    f += Check("Insert", Join(names) == "start,a,b,c,d,end");
    names.RemoveAt(0);
    names.RemoveAt(names.Count() - 1);
    f += Check("RemoveAt ends", Join(names) == "a,b,c,d");
    names.RemoveAt(1);
    f += Check("RemoveAt middle", Join(names) == "a,c,d");
    f += Check("IndexOf", names.IndexOf("c") == 1 && names.IndexOf("zz") == -1);
    f += Check("Contains", names.Contains("d") && !names.Contains("zz"));
    f += Check("Remove", names.Remove("a") && !names.Remove("zz") && Join(names) == "c,d");
    names.AddRange(new string[] { "x", "y" });
    f += Check("AddRange", Join(names) == "c,d,x,y");
    names.Reverse();
    f += Check("Reverse", Join(names) == "y,x,d,c");
    var array = names.ToArray();
    array[0] = "changed";
    f += Check("ToArray", array.Length == 4 && array[3] == "c" && names.Get(0) == "y");
    names.Clear();
    f += Check("Clear", names.Count() == 0 && Join(names) == "");
    names.Add("again");
    f += Check("Add after Clear", names.Count() == 1 && names.Get(0) == "again");

    // ---- sorting ----
    var numbers = List<int>.Create();
    int seed = 12345;
    for (var i = 0; i < 500; i += 1)
    {
        seed = (seed * 1103 + 12345) % 100003;
        numbers.Add(seed);
    }
    f += Check("unsorted", !IsSorted(numbers));
    numbers.Sort();
    f += Check("Sort int", IsSorted(numbers) && numbers.Count() == 500);

    var words = List<string>.Create();
    words.Add("pear");
    words.Add("apple");
    words.Add("fig");
    words.Add("banana");
    words.Sort();
    f += Check("Sort string", Join(words) == "apple,banana,fig,pear");

    var versions = List<Version>.Create();
    versions.Add(Version { Major = 2, Minor = 1 });
    versions.Add(Version { Major = 1, Minor = 9 });
    versions.Add(Version { Major = 2, Minor = 0 });
    versions.Add(Version { Major = 1, Minor = 10 });
    versions.Sort();
    f += Check("Sort struct", versions.Get(0).Minor == 9 && versions.Get(1).Minor == 10 && versions.Get(2).Minor == 0 &&
                              versions.Get(3).Minor == 1);
    f += Check("IndexOf struct", versions.IndexOf(Version { Major = 2, Minor = 0 }) == 2 &&
                                 !versions.Contains(Version { Major = 9, Minor = 9 }));

    // ---- lists of lists ----
    var outer = List<List<int>>.Create();
    for (var i = 0; i < 3; i += 1)
    {
        var inner = List<int>.Create();
        inner.Add(i);
        inner.Add(i * 10);
        outer.Add(inner);
    }
    f += Check("list of lists", outer.Count() == 3 && outer.Get(2).Get(1) == 20 && outer.Get(1).Count() == 2);

    // ---- many elements with ARC ----
    var big = List<string>.Create();
    for (var i = 0; i < 2000; i += 1)
        big.Add("item" + i);
    for (var i = 0; i < 1000; i += 1)
        big.RemoveAt(0);
    f += Check("many strings", big.Count() == 1000 && big.Get(0) == "item1000" && big.Get(999) == "item1999");

    return f;
}
