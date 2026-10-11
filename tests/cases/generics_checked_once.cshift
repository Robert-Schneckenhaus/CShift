// Generic bodies are checked once with unknown type parameters: nothing that depends on a type parameter is reported
// there, and every instantiation is generated as before.
// expect-exit: 0
// expect-stdout-64: 3 33032x xxx22313
// expect-stdout-32: 3 33032x xxx2239

using System;
enum Color : uint8 { Red, Green }
struct Holder<T, TKey> where TKey : IEquatable<TKey>, IHashable
{
    T[] Items;
    Dictionary<TKey, T> Map;
    List<T> Values;
    int Size() { return sizeof(T) + Items.Length + Values.Count(); }
    T First() { return Items[0]; }
    void Put(TKey k, T v) { Map.Set(k, v); Values.Add(v); }
    static Holder<T, TKey> Create() { return Holder<T, TKey> { Items = new T[4], Map = Dictionary<TKey, T>.Create(), Values = List<T>.Create() }; }
}
int CountOf<T>() { return Enum<T>.Count; }
string Show<T>(T x)
{
    T copy = default(T);
    T[] arr = [x, copy];
    Func<T, T> g = y => y;
    string s = $"{x} {x.ToString()}";
    bool eq = x == copy;
    var list = List<T>.Create();
    list.Add(x);
    foreach (var item in arr)
        s += item.ToString();
    return s + g(x).ToString() + arr.Length.ToString();
}
TOut Map<TIn, TOut>(TIn v, Func<TIn, TOut> fn) { return fn(v); }
int Main()
{
    var h = Holder<string, int>.Create();
    h.Put(1, "a");
    Console.WriteLine(Show(3) + Show("x") + CountOf<Color>().ToString() + Map<int, int>(2, x => x + 1).ToString() + h.Size().ToString());
    return 0;
}
