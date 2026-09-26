// CShift test program.
//
// Build and run together with mathlib.csh:
//     cshiftc test.csh mathlib.csh -o test --run
//
// Every check prints nothing on success and "FAIL: <name>" on failure.
// The program prints a summary and returns the number of failed checks.
// Output that depends on execution order (using/Dispose) is printed and compared
// against tests/test.expected by the test runner.

using MathLib;

// ===========================================================================
// Test infrastructure
// ===========================================================================

struct Tester
{
    int Passed;
    int Failed;

    void Check(string name, bool ok)
    {
        if (ok)
        {
            Passed += 1;
        }
        else
        {
            Failed += 1;
            Console.WriteLine("FAIL: " + name);
        }
    }
}

// ===========================================================================
// Types used by the tests
// ===========================================================================

struct Vec2
{
    float X;
    float Y;

    float Length()
    {
        return sqrt(X * X + Y * Y);
    }

    Vec2 Add(const ref Vec2 other)
    {
        return Vec2 { X = X + other.X, Y = Y + other.Y };
    }

    void Scale(float f)
    {
        X *= f;
        Y *= f;
    }

    static Vec2 Zero()
    {
        return new Vec2();
    }
}

struct Rect2
{
    Vec2 Min;
    Vec2 Max;

    float Area()
    {
        return (Max.X - Min.X) * (Max.Y - Min.Y);
    }
}

struct Person
{
    string Name;
    int Age;
}

struct Counter
{
    int _value; // private: leading underscore
    int Step;

    void Increment()
    {
        _value += Step;
    }

    int Get()
    {
        return _value;
    }
}

struct Animal
{
    int Age;
    string Name;

    string Describe()
    {
        return Name + ":" + Age;
    }

    int Legs()
    {
        return 4;
    }
}

struct Dog : Animal
{
    int Tricks;
}

struct Bird : Animal
{
    int WingSpan;

    int Legs()
    {
        return 2;
    }
}

enum Color : uint8
{
    Red,
    Green = 5,
    Blue
}

enum Flags : int32
{
    None = 0,
    A = 1,
    B = 2,
    C = 4
}

interface IShape
{
    float Area();
}

struct Rect : IShape
{
    float W;
    float H;

    float Area()
    {
        return W * H;
    }
}

struct Quad : IShape
{
    float Side;

    float Area()
    {
        return Side * Side;
    }
}

struct Version : IComparable<Version>
{
    int Major;
    int Minor;

    int CompareTo(Version other)
    {
        if (Major != other.Major)
            return Major.CompareTo(other.Major);
        return Minor.CompareTo(other.Minor);
    }
}

struct Pair<T>
{
    T First;
    T Second;

    T Sum()
    {
        return First;
    }

    Pair<T> Swapped()
    {
        return Pair<T> { First = Second, Second = First };
    }
}

struct Box<T>
{
    T Value;
}

struct Res : IDisposable
{
    int Id;

    void Dispose()
    {
        Console.WriteLine("dispose " + Id);
    }
}

// ===========================================================================
// Free functions used by the tests
// ===========================================================================

T Max<T>(T a, T b)
    where T : IComparable<T>
{
    if (a.CompareTo(b) >= 0)
        return a;
    return b;
}

float TotalArea<T>(T a, T b)
    where T : IShape
{
    return a.Area() + b.Area();
}

T Unbox<T>(Box<T> box)
{
    return box.Value;
}

void Swap<T>(ref T a, ref T b)
{
    var tmp = a;
    a = b;
    b = tmp;
}

string Describe(int v) { return "int"; }
string Describe(double v) { return "double"; }
string Describe(float v) { return "float"; }
string Describe(string v) { return "string"; }
string Describe(bool v) { return "bool"; }

void Bump(ref Vec2 v)
{
    v.X += 1;
}

float Dot(const ref Vec2 a, const ref Vec2 b)
{
    return a.X * b.X + a.Y * b.Y;
}

// Methods called on a const ref parameter operate on a copy, so the caller's value stays untouched.
float ScaledX(const ref Vec2 v)
{
    v.Scale(2);
    return v.X;
}

void PrintAge(const ref Animal a)
{
    Console.WriteLine("age " + a.Age);
}

int Fib(int n)
{
    if (n < 2)
        return n;
    return Fib(n - 1) + Fib(n - 2);
}

int64 Factorial(int n)
{
    int64 result = 1;
    for (var i = 2; i <= n; i += 1)
        result *= i;
    return result;
}

bool Touch(ref int counter)
{
    counter += 1;
    return true;
}

string ColorName(Color c)
{
    switch (c)
    {
        case Color.Red:
            return "red";
        case Color.Green:
            return "green";
        default:
            return "other";
    }
}

Error<int> Parse(string text)
{
    if (text.Length == 0)
        return error("empty");

    int value = 0;
    foreach (var c in text)
    {
        if (c < '0' || c > '9')
            return error("bad char", 2);
        value = value * 10 + (c - '0');
    }
    return value;
}

Error<int> Sum(string a, string b)
{
    var x = try Parse(a);
    var y = try Parse(b);
    return x + y;
}

Error<string> Greeting(string name)
{
    if (name.Length == 0)
        return error("no name");
    return "Hello, " + name;
}

Error<string> Decorated(string name)
{
    var g = try Greeting(name);
    return g + "!";
}

Optional<int> FindIndex(int[] arr, int needle)
{
    for (var i = 0; i < arr.Length; i += 1)
    {
        if (arr[i] == needle)
            return i;
    }
    return null;
}

Optional<string> Lookup(int id)
{
    if (id == 1)
        return "one";
    return null;
}

Error<Res> OpenRes(int id)
{
    if (id < 0)
        return error("invalid id");
    return Res { Id = id };
}

// "using" combined with "try": the resource is disposed when a later "try" returns the error.
Error<int> UseRes(int id, bool fail)
{
    using r = try OpenRes(id);
    Console.WriteLine("using " + r.Id);
    if (fail)
    {
        var bad = try OpenRes(-1);
        Console.WriteLine("not reached");
    }
    return r.Id * 2;
}

// ===========================================================================
// Tests
// ===========================================================================

void TestArithmetic(ref Tester t)
{
    t.Check("precedence 1", 2 + 3 * 4 == 14);
    t.Check("precedence 2", (2 + 3) * 4 == 20);
    t.Check("left assoc", 10 - 4 - 3 == 3);
    t.Check("int division", 7 / 2 == 3);
    t.Check("negative division", -7 / 2 == -3);
    t.Check("modulo", 7 % 3 == 1);
    t.Check("negative modulo", -7 % 3 == -1);

    int64 big = 5000000000;
    t.Check("int64 literal", big == 5000000000);
    t.Check("int64 mul", big * 2 == 10000000000);
    uint8 small = 200;
    t.Check("uint8 promotion", small + small == 400);
    uint64 huge = 18446744073709551615;
    t.Check("uint64 max", huge == uint64.MaxValue);

    t.Check("float math", 1.5 + 2.25 == 3.75);
    float f = 2.5;
    t.Check("float literal adapt", f * 2 == 5.0f);
    double d = 1.0 / 4;
    t.Check("double", d == 0.25);

    t.Check("cast truncation", (uint8)300 == 44);
    t.Check("float to int", (int)3.99 == 3);
    t.Check("negative float to int", (int)(-2.7) == -2);
    t.Check("int to float", (float)7 / 2 == 3.5f);
    t.Check("saturating cast", (int)1e20 == int.MaxValue);
    t.Check("min value", int.MinValue == -2147483648);

    int x = 0xF0;
    t.Check("or", (x | 0x0F) == 0xFF);
    t.Check("and", (0xFF & 0x3C) == 0x3C);
    t.Check("xor", (0xFF ^ 0x0F) == 0xF0);
    t.Check("not", ~0 == -1);
    t.Check("shift left", (1 << 10) == 1024);
    t.Check("shift right arithmetic", (-16 >> 2) == -4);
    t.Check("binary literal", 0b1010 == 10);
    t.Check("digit separators", 1_000_000 == 1000000);

    int y = 3;
    y += 4;
    y *= 2;
    y -= 1;
    y /= 3;
    y %= 3;
    t.Check("compound arithmetic", y == 1);
    y = 1;
    y <<= 4;
    y |= 3;
    y &= 0x13;
    y ^= 1;
    y >>= 1;
    t.Check("compound bit ops", y == 9);

    int big32 = int.MaxValue;
    int wrapped = unchecked(big32 + 1);
    t.Check("unchecked expression", wrapped == int.MinValue);
    unchecked
    {
        uint u = 0;
        u -= 1;
        t.Check("unchecked block", u == uint.MaxValue);
    }

    char c = 'a';
    c += 1;
    t.Check("char arithmetic", c == 'b');
    t.Check("char cast", (char)(c + 1) == 'c');
    t.Check("char range", c >= 'a' && c <= 'z');
    t.Check("char to int", 'A' + 1 == 66);
}

void TestControlFlow(ref Tester t)
{
    // while / break / continue
    int i = 0;
    int sum = 0;
    while (true)
    {
        i += 1;
        if (i > 10)
            break;
        if (i % 2 == 0)
            continue;
        sum += i;
    }
    t.Check("while/break/continue", sum == 25);

    // do-while runs at least once
    int n = 0;
    do
    {
        n += 1;
    }
    while (n < 0);
    t.Check("do-while", n == 1);

    // nested for with break affecting only the inner loop
    int pairs = 0;
    for (var a = 0; a < 5; a += 1)
    {
        for (var b = 0; b < 5; b += 1)
        {
            if (b > a)
                break;
            pairs += 1;
        }
    }
    t.Check("nested for", pairs == 15);

    // switch on int with grouped labels
    int r = 0;
    int k = 2;
    switch (k)
    {
        case 1:
        case 2:
            r = 12;
            break;
        case 3:
            r = 3;
            break;
        default:
            r = -1;
            break;
    }
    t.Check("switch grouped", r == 12);

    // switch on string
    string cmd = "sub";
    int res = 0;
    switch (cmd)
    {
        case "add":
            res = 1;
            break;
        case "sub":
            res = 2;
            break;
        default:
            res = 3;
            break;
    }
    t.Check("switch string", res == 2);

    // switch on enum
    t.Check("switch enum red", ColorName(Color.Red) == "red");
    t.Check("switch enum green", ColorName(Color.Green) == "green");
    t.Check("switch enum default", ColorName(Color.Blue) == "other");

    // conditional operator
    int v = 7;
    t.Check("ternary", (v > 5 ? "big" : "small") == "big");
    t.Check("nested ternary", (v > 10 ? 1 : v > 5 ? 2 : 3) == 2);

    // short circuit evaluation
    int calls = 0;
    bool s1 = false && Touch(ref calls);
    bool s2 = true || Touch(ref calls);
    t.Check("short circuit", calls == 0 && !s1 && s2);
    bool s3 = true && Touch(ref calls);
    t.Check("no short circuit", calls == 1 && s3);

    // recursion
    t.Check("fib", Fib(15) == 610);
    t.Check("factorial int64", Factorial(20) == 2432902008176640000);
}

void TestStructs(ref Tester t)
{
    // value semantics
    Vec2 p1 = Vec2 { X = 3, Y = 4 };
    Vec2 p2 = p1;
    p2.X = 10;
    t.Check("struct copy", p1.X == 3 && p2.X == 10);
    t.Check("method", p1.Length() == 5);

    // default initialization
    var zero = new Vec2();
    t.Check("default init", zero.X == 0 && zero.Y == 0);
    t.Check("static method", Vec2.Zero().Length() == 0);

    // const ref / ref
    Vec2 sum = p1.Add(ref p1);
    t.Check("const ref arg", sum.X == 6 && sum.Y == 8);
    Bump(ref p1);
    t.Check("ref arg", p1.X == 4);
    t.Check("const ref function", Dot(p1, p1) == 4 * 4 + 4 * 4);
    p1.Scale(2);
    t.Check("mutating method", p1.X == 8 && p1.Y == 8);
    t.Check("method on const ref uses a copy", ScaledX(p1) == 8 && p1.X == 8);

    // nested structs
    var r = Rect2 { Min = Vec2 { X = 1, Y = 1 }, Max = Vec2 { X = 4, Y = 3 } };
    t.Check("nested init", r.Area() == 6);
    r.Max.X = 7;
    t.Check("nested field write", r.Area() == 12);

    // structs containing strings are copied by value, strings are shared/immutable
    var ann = Person { Name = "Ann", Age = 30 };
    var bob = ann;
    bob.Name = "Bob";
    bob.Age += 1;
    t.Check("struct with string", ann.Name == "Ann" && bob.Name == "Bob" && ann.Age == 30 && bob.Age == 31);

    // private fields via methods
    var c = new Counter();
    c.Step = 3;
    c.Increment();
    c.Increment();
    t.Check("private field", c.Get() == 6);

    // inheritance
    var dog = Dog { Age = 3, Name = "Rex", Tricks = 2 };
    t.Check("inherited fields", dog.Age == 3 && dog.Name == "Rex" && dog.Tricks == 2);
    t.Check("inherited method", dog.Describe() == "Rex:3");
    t.Check("inherited legs", dog.Legs() == 4);
    var bird = Bird { Age = 1, Name = "Tweety", WingSpan = 20 };
    t.Check("hidden method", bird.Legs() == 2);
    Animal a = dog;
    t.Check("upcast copy", a.Age == 3 && a.Describe() == "Rex:3");
    PrintAge(dog);

    // namespaces and multiple files
    t.Check("namespace function", Square(7) == 49);
    t.Check("qualified function", MathLib.Square(3) == 9);
    t.Check("forward reference", SumOfSquares(3, 4) == 25);
    var p3 = Point3 { X = 1, Y = 2, Z = 3 };
    t.Check("namespace struct", p3.Sum() == 6);
    MathLib.Point3 p4 = MathLib.Point3 { X = 5 };
    t.Check("qualified struct", p4.Sum() == 5);
    t.Check("namespace enum", (int)Mode.Off == 11);
}

void TestEnums(ref Tester t)
{
    t.Check("enum default value", (int)Color.Red == 0);
    t.Check("enum explicit value", (int)Color.Green == 5);
    t.Check("enum auto increment", (int)Color.Blue == 6);
    Color c = Color.Blue;
    t.Check("enum compare", c == Color.Blue && c != Color.Red);
    t.Check("enum from int", (Color)5 == Color.Green);

    Flags f = Flags.A | Flags.C;
    t.Check("flags or", (f & Flags.C) == Flags.C);
    t.Check("flags and", (f & Flags.B) == Flags.None);
}

void TestArrays(ref Tester t)
{
    int[] arr = new int[5];
    for (var i = 0; i < arr.Length; i += 1)
        arr[i] = i * i;
    t.Check("array length", arr.Length == 5);
    var zeros = new int[3];
    t.Check("array zero init", zeros[0] == 0 && zeros[2] == 0 && zeros.Length == 3);

    int total = 0;
    foreach (var v in arr)
        total += v;
    t.Check("foreach", total == 30);

    int[] alias = arr;
    alias[0] = 100;
    t.Check("reference semantics", arr[0] == 100);
    int[] copy = arr.Clone();
    copy[0] = 1;
    t.Check("clone is independent", arr[0] == 100 && copy[0] == 1 && copy[4] == 16);

    var lit = new int[] { 3, 1, 2 };
    t.Check("array literal", lit.Length == 3 && lit[0] == 3 && lit[2] == 2);

    string[] names = new string[] { "a", "bb", "ccc" };
    string[] names2 = names.Clone();
    names2[0] = "changed";
    t.Check("string array", names[0] == "a" && names2[0] == "changed" && names[2].Length == 3);

    var vs = new Vec2[2];
    vs[0].X = 1.5f;
    vs[1] = Vec2 { X = 2, Y = 2 };
    t.Check("struct array", vs[0].X == 1.5f && vs[1].Length() > 2.8f && vs[1].Length() < 2.9f);

    var people = new Person[2];
    people[0] = Person { Name = "P0", Age = 1 };
    people[1].Name = "P1";
    var copyPeople = people.Clone();
    t.Check("array of ARC structs", copyPeople[0].Name == "P0" && copyPeople[1].Name == "P1");

    int64 acc = 0;
    var big = new int64[] { 1, 2, 3 };
    foreach (int64 e in big)
        acc += e;
    t.Check("foreach with declared type", acc == 6);

    string word = "abc";
    string chars = "";
    foreach (var ch in word)
        chars += (char)(ch - 32);
    t.Check("foreach over string", chars == "ABC");
}

void TestStrings(ref Tester t)
{
    string a = "Hello";
    string b = a + ", " + "World";
    t.Check("concat", b == "Hello, World");
    t.Check("length", b.Length == 12);
    t.Check("index", b[1] == 'e');
    t.Check("substring", b.Substring(7) == "World" && b.Substring(0, 5) == a);
    t.Check("not equal", a != b);

    int k = 77;
    t.Check("int to string", k.ToString() == "77" && (-5).ToString() == "-5");
    t.Check("concat int", "n=" + 42 == "n=42");
    t.Check("concat double", "pi=" + 2.5 == "pi=2.5");
    t.Check("concat bool", "x=" + true == "x=true");
    t.Check("concat char", "c=" + 'z' == "c=z");
    t.Check("float to string", (1.5f).ToString() == "1.5");

    string nothing = null;
    t.Check("null string", nothing == null && nothing.Length == 0);
    t.Check("null concat", nothing + "x" == "x");
    string empty = "";
    t.Check("empty string", empty.Length == 0 && empty != null && empty == nothing);

    t.Check("escapes", "a\tb\n".Length == 4 && "\x41" == "A" && "q\"q".Length == 3);
    t.Check("utf8 length", "héllo".Length == 6);

    // immutability: concatenation creates a new string
    string c = a;
    c += "!";
    t.Check("immutable", a == "Hello" && c == "Hello!");
    string dup = a.Clone();
    t.Check("string clone", dup == a);
    string acc = "";
    for (var i = 0; i < 5; i += 1)
        acc += i;
    t.Check("concat in loop", acc == "01234");
}

void TestErrorAndOptional(ref Tester t)
{
    var ok = Parse("123");
    if (ok is int v)
        t.Check("error value", v == 123);
    else
        t.Check("error value", false);
    t.Check("error bool true", ok is int);

    var bad = Parse("12x");
    t.Check("error is error", bad is error);
    t.Check("error message", bad.Message == "bad char");
    t.Check("error code", bad.Code == 2);
    t.Check("error is-pattern fails", !(bad is int));

    var empty = Parse("");
    t.Check("error without code", empty.Message == "empty" && empty.Code == 0);

    // try propagation
    var s1 = Sum("40", "2");
    if (s1 is int total)
        t.Check("try success", total == 42);
    else
        t.Check("try success", false);
    var s2 = Sum("40", "z");
    t.Check("try propagates error", s2 is error e1 && e1.Message == "bad char" && e1.Code == 2);

    // Error<string> (ARC payload)
    if (Decorated("World") is string text)
        t.Check("error string payload", text == "Hello, World!");
    else
        t.Check("error string payload", false);
    t.Check("error string failure", Decorated("") is error e2 && e2.Message == "no name");

    // switch with patterns
    var pr = Parse("9");
    int seen = 0;
    switch (pr)
    {
        case int x:
            seen = x;
            break;
        default:
            seen = -1;
            break;
    }
    t.Check("switch pattern", seen == 9);

    // "case error e" matches a failure and binds the whole result
    var failure = Parse("x");
    string message = "";
    switch (failure)
    {
        case int x:
            message = "value";
            break;
        case error e:
            message = e.Message;
            break;
    }
    t.Check("switch error pattern", message.Length > 0 && message != "value");
    t.Check("is error pattern", failure is error bad && bad.Message == message && !(Parse("77") is error));

    // Optional<T>
    var data = new int[] { 5, 6, 7 };
    if (FindIndex(data, 7) is int idx)
        t.Check("optional value", idx == 2);
    else
        t.Check("optional value", false);
    t.Check("optional absent", FindIndex(data, 99) == null);
    t.Check("optional == null", FindIndex(data, 99) == null && FindIndex(data, 5) != null);

    if (Lookup(1) is string one)
        t.Check("optional string", one == "one");
    else
        t.Check("optional string", false);
    t.Check("optional string absent", Lookup(2) == null);

    Optional<int> assigned = 5;
    t.Check("implicit wrap", assigned is int);
    assigned = null;
    t.Check("assign null", assigned == null);
    Optional<int> defaulted;
    t.Check("default is absent", defaulted == null);
}

void TestGenerics(ref Tester t)
{
    t.Check("Max<int> inferred", Max(3, 9) == 9);
    t.Check("Max<int> explicit", Max<int>(9, 3) == 9);
    t.Check("Max<double>", Max(2.5, 1.5) == 2.5);
    t.Check("Max<int64>", Max(5000000000, 1) == 5000000000);

    var v1 = Version { Major = 1, Minor = 2 };
    var v2 = Version { Major = 1, Minor = 10 };
    var newest = Max(v1, v2);
    t.Check("Max<struct> with constraint", newest.Minor == 10);

    t.Check("constraint IShape", TotalArea(Rect { W = 2, H = 3 }, Rect { W = 1, H = 1 }) == 7);
    t.Check("constraint IShape 2", TotalArea(Quad { Side = 2 }, Quad { Side = 3 }) == 13);

    var pair = Pair<int> { First = 1, Second = 2 };
    var swapped = pair.Swapped();
    t.Check("generic struct", swapped.First == 2 && swapped.Second == 1 && pair.Sum() == 1);
    var sp = Pair<string> { First = "x", Second = "y" };
    t.Check("generic struct with ARC", sp.Swapped().First == "y");
    var nested = Pair<Pair<int>> { First = pair, Second = swapped };
    t.Check("nested generic", nested.Second.First == 2);

    var box = Box<string> { Value = "boxed" };
    t.Check("inference through generic struct", Unbox(box) == "boxed");
    var ibox = Box<int> { Value = 42 };
    t.Check("Unbox<int>", Unbox(ibox) == 42);

    int a = 1;
    int b = 2;
    Swap(ref a, ref b);
    t.Check("generic ref swap", a == 2 && b == 1);
    string s1 = "left";
    string s2 = "right";
    Swap(ref s1, ref s2);
    t.Check("generic ref swap string", s1 == "right" && s2 == "left");
}

void TestOverloads(ref Tester t)
{
    t.Check("overload int", Describe(5) == "int");
    t.Check("overload double", Describe(2.5) == "double");
    t.Check("overload float", Describe(2.5f) == "float");
    t.Check("overload string", Describe("s") == "string");
    t.Check("overload bool", Describe(true) == "bool");
    int8 small = 3;
    t.Check("overload widening", Describe(small) == "int");
}

void UsingEarlyReturn(bool early)
{
    using a = new Res { Id = 1 };
    using b = new Res { Id = 2 };
    Console.WriteLine("body " + early);
    if (early)
        return;
    Console.WriteLine("end");
}

void TestUsing(ref Tester t)
{
    UsingEarlyReturn(true);
    UsingEarlyReturn(false);

    for (var i = 0; i < 3; i += 1)
    {
        using r = new Res { Id = 10 + i };
        if (i == 1)
            continue;
        if (i == 2)
            break;
        Console.WriteLine("loop " + i);
    }

    using (var r = new Res { Id = 20 })
    {
        Console.WriteLine("in block");
    }
    Console.WriteLine("after block");
    t.Check("using compiled", true);
}

void TestUsingTry(ref Tester t)
{
    var a = UseRes(3, false);
    if (a is int v)
        t.Check("using+try ok", v == 6);
    else
        t.Check("using+try ok", false);
    var b = UseRes(4, true);
    t.Check("using+try error", b is error e3 && e3.Message == "invalid id");
    var c = UseRes(-1, false);
    t.Check("try before using", c is error);
}

extern "C" int strlen(char* str);
extern "C" int abs(int x);
extern "C" int printf(char* format, ...);

void TestUnsafeAndFfi(ref Tester t)
{
    t.Check("extern call", abs(-5) == 5);

    unsafe
    {
        string s = "héllo";
        char* p = s.CStr();
        t.Check("strlen", strlen(p) == 6);
        printf("printf: %d %s %.2f\n".CStr(), 42, "text".CStr(), 1.5);

        int* buf = (int*)Memory.Allocate(4 * sizeof(int));
        for (var i = 0; i < 4; i += 1)
            buf[i] = i * 10;
        int* q = buf + 2;
        t.Check("pointer arithmetic", *q == 20);
        *q = 99;
        t.Check("pointer write", buf[2] == 99 && *(buf + 2) == 99);
        t.Check("pointer difference", q - buf == 2);
        Memory.Free(buf);

        int local = 5;
        int* lp = &local;
        *lp += 1;
        t.Check("address-of", local == 6);

        t.Check("sizeof", sizeof(int) == 4 && sizeof(int64) == 8 && sizeof(Vec2) == 8);
    }
}

int Main()
{
    var t = new Tester();

    TestArithmetic(ref t);
    TestControlFlow(ref t);
    TestStructs(ref t);
    TestEnums(ref t);
    TestArrays(ref t);
    TestStrings(ref t);
    TestErrorAndOptional(ref t);
    TestGenerics(ref t);
    TestOverloads(ref t);
    TestUsing(ref t);
    TestUsingTry(ref t);
    TestUnsafeAndFfi(ref t);

    Console.WriteLine("passed: " + t.Passed + ", failed: " + t.Failed);
    return t.Failed;
}
