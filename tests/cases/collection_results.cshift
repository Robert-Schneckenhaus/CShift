// A collection expression becomes the T of an Optional<T> or Error<T> (return values, variables, arguments): the T is
// built as usual and then wrapped, also nested (Error<Optional<ReadOnlySlice<int>>>).
// expect-exit: 0
// expect-stdout: 8 none 3 bob no names 5 3
// expect-stdout: take 2

using System;
Optional<Fixed<int, 2>> FindPair(bool ok)
{
    if (ok)
        return [7, 8];
    return null;
}
Optional<int[]> FindAll(bool ok)
{
    if (!ok)
        return null;
    return [1, 2, 3];
}
Error<List<string>> Names(bool ok)
{
    if (!ok)
        return error("no names");
    return ["ann", "bob"];
}
Error<Optional<ReadOnlySlice<int>>> Nested()
{
    return [4, 5];
}
void Take(Optional<Slice<int>> values)
{
    if (values is Slice<int> s)
        Console.WriteLine("take " + s.Length.ToString());
}
int Main()
{
    string text = "";
    if (FindPair(true) is Fixed<int, 2> p)
        text += p[1].ToString();
    if (FindPair(false) == null)
        text += " none";
    if (FindAll(true) is int[] a)
        text += " " + a.Length.ToString();
    if (Names(true) is List<string> n)
        text += " " + n.Get(1);
    if (Names(false) is error e)
        text += " " + e.Message;
    if (Nested() is Optional<ReadOnlySlice<int>> o && o is ReadOnlySlice<int> r)
        text += " " + r[1].ToString();
    Optional<Fixed<float, 3>> local = [1, 2, 3];
    if (local is Fixed<float, 3> l)
        text += " " + l[2].ToString();
    Console.WriteLine(text);
    Take([1, 2]);
    return 0;
}
