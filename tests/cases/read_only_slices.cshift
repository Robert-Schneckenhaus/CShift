// ReadOnlySlice<T>: a view of part of an array that cannot change the elements. Arrays, Slice<T> and collection
// expressions convert to it for free; indexing (also ^n), slicing, foreach, Length, ToArray() and spreads work like
// with Slice<T>.
// expect-exit: 0
// expect-stdout: 10 2 5 4 3
// expect-stdout: 6 3 7
// expect-stdout: copy 99 1
// expect-stdout: generic 4 c
// expect-stdout: spread 1 2 3 4 5 6

using System;

int Sum(ReadOnlySlice<int> values)
{
    int total = 0;
    foreach (var v in values)
        total += v;
    return total;
}

T Last<T>(ReadOnlySlice<T> values)
{
    return values[^1];
}

int Main()
{
    int[] a = [1, 2, 3, 4];
    ReadOnlySlice<int> all = a;
    ReadOnlySlice<int> tail = all[1..];
    Console.WriteLine(Sum(a).ToString() + " " + tail[0].ToString() + " " + Sum(all[1..3]).ToString() + " " +
                      all.Length.ToString() + " " + tail.Length.ToString());

    Slice<int> writable = a[..3];
    ReadOnlySlice<int> view = writable;          // a Slice<T> converts, never the other way
    ReadOnlySlice<int> made = [3, 4];
    Console.WriteLine(Sum(view).ToString() + " " + view[^1].ToString() + " " + Sum(made).ToString());

    int[] copy = view.ToArray();                  // copying out is explicit and gives a normal array
    copy[0] = 99;
    Console.WriteLine("copy " + copy[0].ToString() + " " + a[0].ToString());

    string[] names = ["a", "b", "c"];
    Console.WriteLine("generic " + Last(a).ToString() + " " + Last<string>(names));

    int[] joined = [..view, ..made[1..], 5, 6];
    string text = "spread";
    foreach (var j in joined)
        text += " " + j.ToString();
    Console.WriteLine(text);
    return 0;
}
