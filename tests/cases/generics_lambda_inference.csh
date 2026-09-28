// Type arguments inferred from lambdas: the result type of the lambda's body (an expression or the first return of a
// block), once its parameter types are known from the other arguments; also in a chain and inside another lambda.
// expect-exit: 0
// expect-stdout: Ann Bob
// expect-stdout: 31 84 47
// expect-stdout: 3 2
// expect-stdout: 3!
// expect-stdout: 23

using System;
struct Person { string Name; int Age; }
TOut Map<TIn, TOut>(TIn v, Func<TIn, TOut> fn) { return fn(v); }
TOut Chain<TA, TB, TOut>(TA a, Func<TA, TB> f, Func<TB, TOut> g) { return g(f(a)); }
int Nested()
{
    var nums = List<int>.Create();
    nums.Add(1);
    nums.Add(2);
    int factor = 10;
    Func<int, string> describe = n => {
        var scaled = nums.Select(x => x * factor + n);
        return scaled.Get(1).ToString();
    };
    Console.WriteLine(describe(3));
    return 0;
}

int Main()
{
    var people = List<Person>.Create();
    people.Add(Person { Name = "Ann", Age = 31 });
    people.Add(Person { Name = "Bob", Age = 42 });
    var names = people.Select(p => p.Name);
    var ages = people.Select(p => { if (p.Age > 40) return p.Age * 2; return p.Age; });
    int offset = 5;
    var shifted = people.Select(p => p.Age + offset);
    Console.WriteLine(names.Get(0) + " " + names.Get(1));
    Console.WriteLine(ages.Get(0).ToString() + " " + ages.Get(1).ToString() + " " + shifted.Get(1).ToString());
    Console.WriteLine(Map(2, x => x + 1).ToString() + " " + Map("ab", s => s.Length).ToString());
    Console.WriteLine(Chain(3, x => x.ToString(), s => s + "!"));
    return Nested();
}
