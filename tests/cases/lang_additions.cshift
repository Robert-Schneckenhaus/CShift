// Smaller language additions: indexers (x[k] is x.Get(k), x[k] = v is x.Set(k, v)), C#'s "Color Color" rule,
// Error<Optional<T>> (tested with 'is', never as a bare condition), 'thread' and 'where' as ordinary names, and round-trip float formatting.
// Main returns the number of failed checks.
// expect-exit: 0

using System;

enum Color : int32 { Red, Green, Blue }

struct Pixel
{
    Color Color;
    int X;

    bool IsGreen() { return Color == Color.Green; }
    void MakeBlue() { Color = Color.Blue; }
    static Pixel Make() { return Pixel { Color = Color.Green, X = 1 }; }
}

struct Size
{
    int W;
    int H;
    static Size Square(int n) { return Size { W = n, H = n }; }
}

struct Box
{
    Size Size;
    int Area() { return Size.W * Size.H; }
    void Reset() { Size = Size.Square(2); }
}

// a struct with its own indexer
struct Grid
{
    int[] Cells;
    int Width;

    static Grid Create(int width, int height)
    {
        return Grid { Cells = new int[width * height], Width = width };
    }

    int Get(int index) { return Cells[index]; }
    void Set(int index, int value) { Cells[index] = value; }
}

Error<Optional<int>> Find(List<int> values, int wanted)
{
    if (wanted < 0)
        return error("negative");
    for (var i = 0; i < values.Count(); i += 1)
    {
        if (values[i] == wanted)
            return i;
    }
    return null;
}

T Same<T>(T value) where T : IEquatable<T>
{
    return value;
}

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

    // indexers
    var list = List<int>.Create();
    list.Add(10);
    list.Add(20);
    failed += Check("list get", list[0] == 10 && list[1] == 20);
    list[1] = 25;
    list[0] += 5;
    failed += Check("list set", list[0] == 15 && list[1] == 25);
    var names = List<string>.Create();
    names.Add("a");
    names[0] = names[0] + "b";
    names[0] += "c";
    failed += Check("list of strings", names[0] == "abc");
    var ages = Dictionary<string, int>.Create();
    ages["Ann"] = 41;
    ages["Ann"] += 1;
    ages["Bob"] = 7;
    failed += Check("dictionary", ages["Ann"] == 42 && ages["Bob"] == 7 && ages.Count() == 2);
    var grid = Grid.Create(3, 2);
    grid[4] = 9;
    grid[4] *= 2;
    failed += Check("own indexer", grid[4] == 18 && grid.Cells[4] == 18);
    int[] plain = new int[3];
    plain[1] = 4;
    plain[1] += 1;
    failed += Check("array still works", plain[1] == 5);

    // Color Color
    var p = Pixel.Make();
    failed += Check("color color field", p.IsGreen());
    p.MakeBlue();
    failed += Check("color color assign", p.Color == Color.Blue);
    Color Color = Color.Red;
    failed += Check("color color local", Color == Color.Red);
    var box = Box { Size = Size.Square(3) };
    failed += Check("struct color color", box.Area() == 9);
    box.Reset();
    failed += Check("struct color color static", box.Area() == 4);

    // Error<Optional<T>>
    var values = List<int>.Create();
    values.Add(5);
    values.Add(8);
    var found = Find(values, 8);
    failed += Check("found", found is Optional<int> f && f is int index && index == 1);
    var missing = Find(values, 3);
    failed += Check("missing", missing is Optional<int> m && !(m is int));
    var bad = Find(values, -1);
    failed += Check("error", !(bad is Optional<int>) && bad.Message == "negative");
    // 'is T v' on Error<Optional<T>>: succeeded and has a value
    failed += Check("is value", found is int direct && direct == 1);
    failed += Check("is value missing", !(missing is int));
    failed += Check("is value error", !(bad is int));

    // contextual keywords
    int where = 2;
    int thread = where * 3;
    failed += Check("contextual", thread == 6 && Same(where) == 2);

    // round-trip floats
    failed += Check("third", (1.0 / 3.0).ToString() == "0.3333333333333333");
    failed += Check("point one", 0.1.ToString() == "0.1");
    failed += Check("sum", (0.1 + 0.2).ToString() == "0.30000000000000004");
    failed += Check("float", ((float)(1.0 / 3.0)).ToString() == "0.33333334");
    failed += Check("parse back", (1.0 / 3.0).ToString().ParseDouble() is double d && d == 1.0 / 3.0);
    return failed;
}
