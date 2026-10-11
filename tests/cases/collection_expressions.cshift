// Collection expressions: [a, b, ..c] becomes the type it is used as - an array (exactly the right length), a
// Slice<T> of a new array, or a struct with 'static Create()' and 'Add(T)' (List<T>, HashSet<T>). ..c spreads an
// array, a slice or a collection with ToArray(). Without a type ('var', foreach, x.Length) it is an array of the
// first element's type.
// expect-exit: 0
// expect-stdout: 3 2 3 0 8 71 15
// expect-stdout: 4 x bob y
// expect-stdout: 3 3
// expect-stdout: 5 z
// expect-stdout: pq
// expect-stdout: 1 2.5

using System;

int Sum(Slice<int> values)
{
    int total = 0;
    foreach (var v in values)
        total += v;
    return total;
}

string[] Names()
{
    return ["ann", "bob"];
}

int Main()
{
    int[] a = [1, 2, 3];
    Slice<int> s = [4, 5];
    var inferred = [10, 20, 30];
    int[] none = [];
    int[] all = [..a, ..s, 6, ..inferred[1..]];
    Console.WriteLine($"{a.Length} {s.Length} {inferred.Length} {none.Length} {all.Length} {Sum(all)} {Sum([7, 8])}");
    List<string> names = ["x", ..Names(), "y"];
    Console.WriteLine($"{names.Count()} {names[0]} {names[2]} {names[3]}");
    HashSet<int> set = [1, 2, 2, 3, ..a];
    Console.WriteLine($"{set.Count()} {[1, 2, 3].Length}");
    List<string> more = [..names, "z"];
    string[] fromList = [..more];
    Console.WriteLine($"{fromList.Length} {fromList[^1]}");
    foreach (var w in ["p", "q"])
        Console.Write(w);
    Console.WriteLine();
    double[] ds = [1, 2.5];
    Console.WriteLine($"{ds[0]} {ds[1]}");
    return 0;
}
