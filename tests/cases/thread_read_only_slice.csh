// A ReadOnlySlice<T> can be passed to a thread: the thread gets its own copy of the elements (strings in them copied
// as well), so later changes of the array are not seen by the thread and no reference count is shared. Arrays and
// slices convert to ReadOnlySlice<T> for free, so 'start Sum(a)' works with an int[].
// expect-exit: 0
// expect-stdout: sum 10 6 0
// expect-stdout: words 3 one-two-three
// expect-stdout: people Ann:3 Bob:4
// expect-stdout: many 400000

using System;

struct Person
{
    string Name;
    ReadOnlySlice<int> Scores;
}

thread int Sum(ReadOnlySlice<int> values)
{
    int total = 0;
    foreach (var v in values)
        total += v;
    return total;
}

thread string Join(ReadOnlySlice<string> words)
{
    return words.Length.ToString() + " " + string.Join("-", words.ToArray());
}

thread string Describe(ReadOnlySlice<Person> people)
{
    string text = "";
    foreach (var p in people)
        text += " " + p.Name + ":" + p.Scores.Length.ToString();
    return text;
}

int Main()
{
    int[] a = [1, 2, 3, 4];
    var t1 = start Sum(a);
    var t2 = start Sum(a[..3]);
    ReadOnlySlice<int> none = [];
    var t3 = start Sum(none);
    a[0] = 100; // after the start: the threads have their own copies
    Console.WriteLine("sum " + t1.Join().ToString() + " " + t2.Join().ToString() + " " + t3.Join().ToString());

    string[] words = ["one", "two", "three"];
    var t4 = start Join(words);
    Console.WriteLine("words " + t4.Join());

    Person[] people = [Person { Name = "Ann", Scores = [1, 2, 3] }, Person { Name = "Bob", Scores = [4, 5, 6, 7] }];
    var t5 = start Describe(people);
    Console.WriteLine("people" + t5.Join());

    // many threads with the same elements at the same time
    int[] big = new int[1000];
    for (var i = 0; i < big.Length; i += 1)
        big[i] = 1;
    var threads = List<Thread<int>>.Create();
    for (var i = 0; i < 400; i += 1)
        threads.Add(start Sum(big));
    int many = 0;
    foreach (var t in threads.ToArray())
        many += t.Join();
    Console.WriteLine("many " + many.ToString());
    return 0;
}
