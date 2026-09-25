// Strings as thread parameters: each thread gets its own copy (also inside structs, Optional<T> and Error<T>), which
// it releases itself. Many threads with the same strings at the same time must not corrupt reference counts.
// A Thread<int> handle may be passed on to another thread; a thread may return a string.
// expect-exit: 0
// expect-stdout: hello world 11
// expect-stdout: Ann/42/yes/fine
// expect-stdout: total 64000
// expect-stdout: joined 5
// expect-stdout: from thread 7

using System;

struct Person
{
    string Name;
    int Age;
    Optional<string> Note;
}

thread string Greet(string a, string b)
{
    string s = a + " " + b;
    return s + " " + s.Length.ToString();
}

thread string Describe(Person p, Optional<string> flag, Error<string> status)
{
    string note = p.Note is string n ? n : "-";
    string f = flag is string x ? x : "no";
    string st = status is string ok ? ok : "error";
    return p.Name + "/" + p.Age.ToString() + "/" + f + "/" + st + (note == "-" ? "" : "");
}

thread int Measure(string text, int rounds)
{
    int total = 0;
    for (var i = 0; i < rounds; i += 1)
    {
        string copy = text;
        total += copy.Length;
    }
    return total;
}

thread int Five()
{
    return 5;
}

thread int JoinOther(Thread<int> other)
{
    return other.Join();
}

thread string Seven()
{
    return "from thread " + (3 + 4).ToString();
}

void Main()
{
    Console.WriteLine((start Greet("hello", "world")).Join());

    var ann = Person { Name = "Ann", Age = 42, Note = "likes tea" };
    Error<string> status = "fine";
    Optional<string> flag = "yes";
    Console.WriteLine((start Describe(ann, flag, status)).Join());

    // the same string handed to many threads at once
    string shared = "0123456789abcdef";
    var threads = List<Thread<int>>.Create();
    for (var i = 0; i < 8; i += 1)
        threads.Add(start Measure(shared, 500));
    int total = 0;
    foreach (var t in threads)
        total += t.Join();
    Console.WriteLine("total " + total.ToString());

    Console.WriteLine("joined " + (start JoinOther(start Five())).Join().ToString());
    Console.WriteLine((start Seven()).Join());
}
