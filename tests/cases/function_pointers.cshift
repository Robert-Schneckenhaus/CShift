// Action / Func: pointers to named functions (no closures)
// expect-stdout: function pointers ok
// expect-stdout: bump

int Square(int x)
{
    return x * x;
}

int Twice(int x)
{
    return x * 2;
}

int Add(int a, int b)
{
    return a + b;
}

int Answer()
{
    return 42;
}

void Nothing()
{
}

void Print(string s)
{
    Console.WriteLine("print: " + s);
}

// overloads: the target type selects one
int Pick(int x)
{
    return x + 1;
}

string Pick(string s)
{
    return s + "!";
}

T Identity<T>(T value)
{
    return value;
}

string Greet(string name)
{
    return "hello " + name;
}

bool IsEven(int v)
{
    return v % 2 == 0;
}

int8 Negate8(int8 v)
{
    return (int8)(-v);
}

int Apply(Func<int, int> f, int value)
{
    return f(value);
}

int Fold(Func<int, int, int> f, int[] values, int start)
{
    int acc = start;
    foreach (var v in values)
        acc = f(acc, v);
    return acc;
}

Func<int, int> Choose(bool square)
{
    if (square)
        return Square;
    return Twice;
}

void Repeat(Action a, int times)
{
    for (var i = 0; i < times; i += 1)
        a();
}

void Bump()
{
    Console.WriteLine("bump");
}

// generic function taking a function; the result type is inferred from the function name
U[] Map<T, U>(T[] values, Func<T, U> f)
{
    U[] result = new U[values.Length];
    for (var i = 0; i < values.Length; i += 1)
        result[i] = f(values[i]);
    return result;
}

struct Handlers
{
    Action<string> OnMessage;
    Func<int, int> Transform;

    void Fire(string text)
    {
        if (OnMessage != null)
            OnMessage(text);
    }

    int Run(int v)
    {
        return Transform(v);
    }

    static int Triple(int v)
    {
        return v * 3;
    }
}

int Main()
{
    // assignment and call
    Func<int, int> f = Square;
    if (f(7) != 49)
        return 1;
    f = Twice;
    if (f(7) != 14)
        return 2;

    // var takes the type of the function
    var g = Add;
    if (g(3, 4) != 7)
        return 3;

    // Func without parameters, Action without parameters
    Func<int> answer = Answer;
    if (answer() != 42)
        return 4;
    Action nothing = Nothing;
    nothing();

    // passing and returning function pointers
    if (Apply(Square, 5) != 25)
        return 5;
    if (Choose(true)(6) != 36 || Choose(false)(6) != 12)
        return 6;
    int[] numbers = new int[4];
    numbers[0] = 1;
    numbers[1] = 2;
    numbers[2] = 3;
    numbers[3] = 4;
    if (Fold(Add, numbers, 0) != 10)
        return 7;

    // Action: the function runs each time
    Repeat(Bump, 2);

    // overloads are resolved by the target type
    Func<int, int> pi = Pick;
    Func<string, string> ps = Pick;
    if (pi(1) != 2 || ps("a") != "a!")
        return 9;

    // generic functions: explicit type arguments or inferred from the target
    Func<int, int> id = Identity<int>;
    Func<string, string> ids = Identity;
    if (id(5) != 5 || ids("x") != "x")
        return 10;

    // Map infers T and U from the function
    int[] squares = Map(numbers, Square);
    if (squares[3] != 16 || squares.Length != 4)
        return 11;
    string[] greetings = Map(new string[] { "a", "b" }, Greet);
    if (greetings[1] != "hello b")
        return 12;

    // bool and small integer parameters
    Func<int, bool> even = IsEven;
    if (!even(4) || even(5))
        return 13;
    Func<int8, int8> neg = Negate8;
    if (neg(5) != -5)
        return 14;

    // null, comparison
    Action<string> none = null;
    if (none != null)
        return 15;
    Action<string> printer = Print;
    if (printer == null || printer != Print)
        return 16;
    Func<int, int> f1 = Square;
    Func<int, int> f2 = Square;
    if (f1 != f2)
        return 17;

    // struct fields
    var h = new Handlers();
    h.Fire("ignored"); // null field is checked by the struct
    h.OnMessage = Print;
    h.Fire("from struct");
    h.OnMessage("direct call of a field");
    h.Transform = Handlers.Triple;
    if (h.Run(4) != 12 || h.Transform(5) != 15)
        return 18;

    // arrays of function pointers
    Func<int, int>[] table = new Func<int, int>[2];
    table[0] = Square;
    table[1] = Twice;
    if (table[0](9) != 81 || table[1](9) != 18)
        return 19;

    // Invoke, default
    if (f.Invoke(10) != 20)
        return 20;
    Func<int, int> zero = default(Func<int, int>);
    if (zero != null)
        return 21;

    // explicit cast of a function name
    var cast = (Func<int, int>)Square;
    if (cast(3) != 9)
        return 22;

    Console.WriteLine("function pointers ok");
    return 0;
}
