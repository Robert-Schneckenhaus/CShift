// The examples of the playground: small programs that show the language (each one compiles; see scripts/playground.sh,
// which checks them with the compiler that is built for the page).
export const examples = [
    {
        name: "Hello, World",
        code: `using System;

int Main(string[] args)
{
    string name = args.Length > 0 ? args[0] : "World";
    Console.WriteLine($"Hello, {name}!");
    return 0;
}
`,
    },
    {
        name: "Lists and lambdas",
        code: `using System;

struct Player
{
    string Name;
    int Score;
}

void Main()
{
    var players = List<Player>.Create();
    players.Add(Player { Name = "Ann", Score = 42 });
    players.Add(Player { Name = "Bob", Score = 17 });
    players.Add(Player { Name = "Cid", Score = 99 });

    var best = players.Where(p => p.Score > 20).Select(p => p.Name);
    foreach (var name in best)
        Console.WriteLine(name);

    int total = 0;
    foreach (var p in players)
        total += p.Score;
    Console.WriteLine($"total {total,5}, average {total / (double)players.Count():F2}");
}
`,
    },
    {
        name: "Errors as values",
        code: `using System;

error ParseError { Empty, NotANumber }

ParseError<int> ParseNumber(string text)
{
    if (text.Length == 0)
        return error("the text is empty", ParseError.Empty);
    int value = 0;
    foreach (char c in text)
    {
        if (c < '0' || c > '9')
            return error($"'{c}' is not a digit", ParseError.NotANumber);
        value = value * 10 + (c - '0');
    }
    return value;
}

Error<int> Sum(string a, string b)
{
    int x = try ParseNumber(a);   // passes a failure on
    int y = try ParseNumber(b);
    return x + y;
}

void Main()
{
    switch (ParseNumber("12x"))
    {
    case int n:
        Console.WriteLine(n);
        break;
    case ParseError.Empty:
        Console.WriteLine("nothing to parse");
        break;
    case error e:
        Console.WriteLine("failed: " + e.Message);
        break;
    }
    if (Sum("40", "2") is int sum)
        Console.WriteLine(sum);
}
`,
    },
    {
        name: "Unions and interfaces",
        code: `using System;

interface IShape
{
    double Area();
}

struct Circle : IShape
{
    double R;
    double Area() { return Math.PI * R * R; }
}

struct Rect : IShape
{
    double W;
    double H;
    double Area() { return W * H; }
}

union Shape : IShape { Circle, Rect }

string Describe(Shape s)
{
    string text = "";
    switch (s)   // every member needs a case (or a default)
    {
    case Circle c:
        text = $"a circle of radius {c.R}";
        break;
    case Rect r:
        text = $"a {r.W} x {r.H} rectangle";
        break;
    }
    return text;
}

void Main()
{
    Shape[] shapes = [Circle { R = 1.0 }, Rect { W = 2.0, H = 3.0 }];
    foreach (var s in shapes)
        Console.WriteLine($"{Describe(s)}: area {s.Area():F2}");
}
`,
    },
    {
        name: "Generics",
        code: `using System;

T Largest<T>(ReadOnlySlice<T> items) where T : IComparable<T>
{
    T best = items[0];
    foreach (var item in items)
    {
        if (item.CompareTo(best) > 0)
            best = item;
    }
    return best;
}

struct Pair<A, B>
{
    A First;
    B Second;
}

void Main()
{
    int[] numbers = [3, 9, 4];
    Console.WriteLine(Largest<int>(numbers));
    Console.WriteLine(Largest<string>(["pear", "apple", "plum"]));

    var pair = Pair<string, int> { First = "answer", Second = 42 };
    Console.WriteLine($"{pair.First} = {pair.Second}");
}
`,
    },
];
