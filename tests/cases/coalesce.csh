// a ?? b: the value of an Optional<T>, or b when it has none (b is only evaluated then); x ??= v sets an Optional<T>
// that has no value.
// expect-stdout: values: 5 7 3
// expect-stdout: optional: none 8
// expect-stdout: calls: 1
// expect-stdout: strings: Ann guest guest-2
// expect-stdout: precedence: 3 4 6 true 2
// expect-stdout: typed: 3000000000 1:2 [1,2]
// expect-stdout: text: Hello, Ann! Hello, World!
// expect-stdout: lookup: 1 0
// expect-stdout: assign: 4 4 none
// expect-stdout: assign strings: first first
// expect-stdout: assign places: 8 nine 10 11
// expect-stdout: assign calls: 1
// expect-stdout: owned: name-1 y
// expect-stdout: global: 6
// expect-stdout: lambda: 4 0

using System;

struct Point
{
    int X;
    int Y;
}

struct Settings
{
    Optional<string> Name;
    Optional<int> Size;
}

int calls = 0;
Optional<int> unset = null;
int fromGlobal = unset ?? 6;

int Counted(int value)
{
    calls += 1;
    return value;
}

string Guest(int n)
{
    return "guest-" + n.ToString();
}

Optional<int> Find(int key)
{
    if (key > 0)
        return key * 2;
    return null;
}

// an Optional<string> that the caller owns
Optional<string> NameOf(int n)
{
    if (n > 0)
        return "name-" + n.ToString();
    return null;
}

string Show(Optional<int> v)
{
    return v is int x ? x.ToString() : "none";
}

int Main()
{
    Optional<int> five = 5;
    Optional<int> none = null;
    Console.WriteLine("values: " + (five ?? 1).ToString() + " " + (none ?? 7).ToString() + " " + (none ?? none ?? 3).ToString());

    // an Optional<T> on the right: the result is an Optional<T>
    Optional<int> stillNone = none ?? none;
    Optional<int> eight = none ?? Find(4) ?? 0;
    Console.WriteLine("optional: " + Show(stillNone) + " " + Show(eight));

    // the right side runs only when the left side has no value
    int a = five ?? Counted(1);
    int b = none ?? Counted(2);
    Console.WriteLine("calls: " + calls.ToString());

    // strings: the value, a literal, an owned temporary (no leaks: --arc-stats)
    Optional<string> name = "Ann";
    Optional<string> nobody = null;
    string guest = nobody ?? "guest";
    Console.WriteLine("strings: " + (name ?? "guest") + " " + guest + " " + (nobody ?? Guest(2)));

    // below + and ||, above ?:, right-associative
    bool flag = false;
    int p1 = none ?? 1 + 2;
    int p2 = (none ?? 1) + 3;
    int p3 = flag ? 0 : five ?? 0 + 1;
    bool p4 = flag || true;
    int p5 = (none ?? 1) * 2;
    Console.WriteLine("precedence: " + p1.ToString() + " " + p2.ToString() + " " + (p3 + 1).ToString() + " " + p4.ToString() + " " +
                      p5.ToString());

    // the right side takes the type of T: a large literal, a typeless new, a collection
    Optional<int64> big = null;
    Optional<Point> point = null;
    Optional<List<int>> list = null;
    Point at = point ?? new { X = 1, Y = 2 };
    List<int> items = list ?? [1, 2];
    Console.WriteLine("typed: " + (big ?? 3000000000).ToString() + " " + at.X.ToString() + ":" + at.Y.ToString() + " [" +
                      items.Get(0).ToString() + "," + items.Get(1).ToString() + "]");

    Console.WriteLine($"text: Hello, {name ?? "you"}! Hello, {nobody ?? "World"}!");

    var counts = Dictionary<string, int>.Create();
    counts.Set("a", 1);
    Console.WriteLine("lookup: " + (counts.TryGet("a") ?? 0).ToString() + " " + (counts.TryGet("b") ?? 0).ToString());

    // ??= only assigns when there is no value
    Optional<int> size = null;
    size ??= 4;
    Optional<int> kept = size;
    kept ??= 5;
    Optional<int> empty = null;
    empty ??= none;
    Console.WriteLine("assign: " + Show(size) + " " + Show(kept) + " " + Show(empty));

    Optional<string> first = null;
    first ??= "first";
    first ??= Guest(3);
    Optional<string> second = first;
    second ??= "second";
    Console.WriteLine("assign strings: " + (first ?? "") + " " + (second ?? ""));

    // fields and array elements
    var settings = Settings { };
    settings.Size ??= 8;
    settings.Size ??= 80;
    settings.Name ??= "nine";
    var slots = new Optional<int>[3];
    slots[1] ??= 10;
    slots[1] ??= 100;
    slots[2] = 11;
    slots[2] ??= 110;
    Console.WriteLine("assign places: " + Show(settings.Size) + " " + (settings.Name ?? "") + " " + Show(slots[1]) + " " +
                      Show(slots[2]));

    // the value of '??=' is only evaluated when it is assigned
    calls = 0;
    Optional<int> once = null;
    once ??= Counted(1);
    once ??= Counted(2);
    Console.WriteLine("assign calls: " + calls.ToString());

    // the left side is a temporary that the statement owns
    Console.WriteLine("owned: " + (NameOf(1) ?? "x") + " " + (NameOf(0) ?? "y"));
    Console.WriteLine("global: " + fromGlobal.ToString());
    Func<Optional<int>, int> orZero = v => v ?? 0;
    Console.WriteLine("lambda: " + orZero(4).ToString() + " " + orZero(null).ToString());
    return a + b == 7 ? 0 : 1;
}
