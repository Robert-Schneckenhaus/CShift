// Lambdas and closures: expression and block bodies, parameter types from the target or written, captured variables
// (copies, taken when the lambda is created), 'this' in methods (a copy), lambdas returning lambdas, closures in a list.
// expect-exit: 0
// expect-stdout: 49
// expect-stdout: v15
// expect-stdout: 12
// expect-stdout: 6
// expect-stdout: hello
// expect-stdout: hi!
// expect-stdout: 9
// expect-stdout: 3
// expect-stdout: c:100
// expect-stdout: 1003
// expect-stdout: 0
// expect-stdout: 10
// expect-stdout: 20

using System;

int Apply(Func<int, int> f, int x) { return f(x); }

struct Counter
{
    int Step;
    string Name;
    Func<int, int> Adder() { return x => x + Step; }
    Func<string> Describe() { return () => $"{Name}:{Step}"; }
}

Func<int, int> MakeAdder(int n) { return x => x + n; }

int Main()
{
    Func<int, int> square = x => x * x;
    Console.WriteLine(square(7));
    int offset = 10;
    string label = "v";
    Func<int, string> show = (int v) => label + (v + offset).ToString();
    Console.WriteLine(show(5));
    Console.WriteLine(Apply(x => x * 3, 4));
    var add5 = MakeAdder(5);
    Console.WriteLine(add5(1));
    Action hello = () => Console.WriteLine("hello");
    hello();
    Action<string> printer = s => { string t = s + "!"; Console.WriteLine(t); };
    printer("hi");
    Func<int, int, int> max = (a, b) => { if (a > b) return a; return b; };
    Console.WriteLine(max(3, 9));
    var c = Counter { Step = 2, Name = "c" };
    var adder = c.Adder();
    c.Step = 100;
    Console.WriteLine(adder(1));
    Console.WriteLine(c.Describe()());
    // nested lambdas capturing through two levels
    int basis = 1000;
    Func<int, Func<int, int>> curry = a => b => a + b + basis;
    Console.WriteLine(curry(1)(2));
    var list = List<Func<int>>.Create();
    for (var i = 0; i < 3; i += 1)
    {
        int copy = i;
        list.Add(() => copy * 10);
    }
    foreach (var g in list)
        Console.WriteLine(g());
    return 0;
}
