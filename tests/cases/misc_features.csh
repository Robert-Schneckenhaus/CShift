// A collection of features that are not covered by test.csh: a generic container written in
// CShift itself, jagged arrays, ref to array elements and fields, structs as Error/Optional
// payloads, char switches and more. Main returns the number of failed checks.
// expect-exit: 0

struct Vec2
{
    float X;
    float Y;
}

struct Named
{
    string Name;
}

struct Big
{
    int64 A;
    int64 B;
    int64 C;
    int64 D;
    string S;
}

struct List<T>
{
    T[] _items;
    int _count;

    void Add(T value)
    {
        if (_items == null || _count == _items.Length)
        {
            var bigger = new T[_count == 0 ? 4 : _count * 2];
            for (var i = 0; i < _count; i += 1)
                bigger[i] = _items[i];
            _items = bigger;
        }
        _items[_count] = value;
        _count += 1;
    }

    T Get(int index)
    {
        if (index >= _count)
            return _items[_items.Length];
        return _items[index];
    }

    int Count()
    {
        return _count;
    }
}

void SetName(ref string s)
{
    s = "set";
}

string Twice(string s)
{
    s = s + s;
    return s;
}

string Repeat(string s, int n)
{
    if (n == 0)
        return "";
    return s + Repeat(s, n - 1);
}

int SumBig(Big b)
{
    return (int)(b.A + b.B + b.C + b.D) + b.S.Length;
}

int Len(const ref Named n)
{
    return n.Name.Length;
}

Error<Vec2> MakeVec(bool ok)
{
    if (!ok)
        return error("nope", 9);
    return Vec2 { X = 1, Y = 2 };
}

Optional<Vec2> MaybeVec(bool ok)
{
    if (ok)
        return Vec2 { X = 3, Y = 4 };
    return null;
}

T First<T>(T[] arr)
{
    return arr[0];
}

T Larger<T>(T a, T b)
    where T : IComparable<T>
{
    if (a.CompareTo(b) > 0)
        return a;
    return b;
}

T LargerOfThree<T>(T a, T b, T c)
    where T : IComparable<T>
{
    return Larger(Larger(a, b), c);
}

int Forever(int n)
{
    while (true)
    {
        n += 1;
        if (n > 5)
            return n;
    }
}

int KindOf(char c)
{
    switch (c)
    {
        case 'a':
        case 'e':
            return 1;
        default:
            return 0;
        case 'z':
            return 26;
    }
}

void Bump(ref int x)
{
    x += 1;
}

void Swap(ref int a, ref int b)
{
    var t = a;
    a = b;
    b = t;
}

int Main()
{
    int failures = 0;

    // Generic container written in CShift
    var list = new List<string>();
    for (var i = 0; i < 10; i += 1)
        list.Add("s" + i);
    if (list.Count() != 10 || list.Get(0) != "s0" || list.Get(9) != "s9")
        failures += 1;
    var ints = new List<int>();
    for (var i = 0; i < 100; i += 1)
        ints.Add(i * i);
    if (ints.Count() != 100 || ints.Get(99) != 9801)
        failures += 1;

    // Jagged arrays
    var jag = new int[3][];
    for (var i = 0; i < jag.Length; i += 1)
    {
        jag[i] = new int[i + 1];
        jag[i][i] = i + 10;
    }
    var jagCopy = jag.Clone();
    jag[2][2] = 99;
    if (jagCopy[2][2] != 99 || jag[1][1] != 11 || jag[0].Length != 1)
        failures += 1;
    var table = new string[][] { new string[] { "a", "b" }, new string[] { "c" } };
    if (table.Length != 2 || table[0][1] != "b" || table[1][0] != "c")
        failures += 1;

    // ref to variables, fields and array elements
    string name = "orig";
    SetName(ref name);
    if (name != "set" || Twice(Twice("ab")) != "abababab" || Repeat("xy", 3) != "xyxyxy")
        failures += 1;
    var nums = new int[] { 1, 2, 3 };
    Bump(ref nums[1]);
    Swap(ref nums[0], ref nums[2]);
    if (nums[0] != 3 || nums[1] != 3 || nums[2] != 1)
        failures += 1;
    var v = new Vec2();
    var counter = new int[1];
    Bump(ref counter[0]);
    Bump(ref counter[0]);
    if (counter[0] != 2)
        failures += 1;

    // structs by value / const ref
    var big = Big { A = 1, B = 2, C = 3, D = 4, S = "abc" };
    if (SumBig(big) != 13)
        failures += 1;
    var named = Named { Name = "hello" };
    if (Len(named) != 5)
        failures += 1;

    // structs as Error / Optional payload
    if (MakeVec(true) is Vec2 mv)
    {
        if (mv.X != 1 || mv.Y != 2)
            failures += 1;
    }
    else
        failures += 1;
    var bad = MakeVec(false);
    if (bad || bad.Code != 9)
        failures += 1;
    if (MaybeVec(true) is Vec2 ov)
    {
        if (ov.Y != 4)
            failures += 1;
    }
    else
        failures += 1;
    if (MaybeVec(false))
        failures += 1;

    // generics calling generics, inference from arrays
    if (LargerOfThree(3, 9, 5) != 9 || LargerOfThree(2.5, 0.5, 1.5) != 2.5)
        failures += 1;
    if (First(new string[] { "x", "y" }) != "x" || First(nums) != 3)
        failures += 1;

    // control flow corner cases
    if (Forever(0) != 6)
        failures += 1;
    if (KindOf('a') != 1 || KindOf('e') != 1 || KindOf('z') != 26 || KindOf('q') != 0)
        failures += 1;
    int loops = 0;
    for (var i = 0; i < 10; i += 1)
    {
        switch (i % 3)
        {
            case 0:
                continue;
            case 1:
                loops += 1;
                break;
            default:
                loops += 10;
                break;
        }
    }
    if (loops != 3 * 1 + 3 * 10)
        failures += 1;

    // modifying a foreach variable does not change the array
    var pts = new Vec2[] { Vec2 { X = 1, Y = 1 }, Vec2 { X = 2, Y = 2 } };
    foreach (var p in pts)
    {
        var q = p;
        q.X = 100;
    }
    if (pts[0].X != 1 || pts[1].X != 2)
        failures += 1;

    // shadowing and nested scopes
    int outer = 1;
    {
        int inner = outer + 1;
        outer = inner * 2;
    }
    if (outer != 4)
        failures += 1;

    return failures;
}
