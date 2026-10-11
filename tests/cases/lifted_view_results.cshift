// A view conversion of the value of an Optional<T> or Error<T> is lifted into the result: Optional<uint16[]> ->
// Optional<ReadOnlySlice<uint16>>, Error<string, E> -> Error<StringSlice> and so on (also empty results, owned
// temporaries and nested into Error<Optional<T>>).
// expect-exit: 0
// expect-stdout: sum 6 sum none
// expect-stdout: text hello chars 5 slice
// expect-stdout: view 30 read 3 missing
// expect-stdout: nested 9 nested none
// expect-stdout: coded abc failed denied true widened 404

using System;

error FileError
{
    NotFound,
    Denied = 13
}

Optional<uint16[]> Find(bool ok)
{
    if (!ok)
        return null;
    return [1, 2, 3];
}
string Sum(Optional<ReadOnlySlice<uint16>> values)
{
    if (values is ReadOnlySlice<uint16> v)
    {
        int total = 0;
        foreach (var x in v)
            total += x;
        return "sum " + total.ToString();
    }
    return "sum none";
}
string Chars(Optional<ReadOnlySlice<char>> text)
{
    if (text is ReadOnlySlice<char> c)
        return "chars " + c.Length.ToString();
    return "chars none";
}
string Text(Optional<StringSlice> text)
{
    if (text is StringSlice s)
        return "text " + s;
    return "text none";
}
// a string prefers StringSlice, also inside an Optional
string Pick(Optional<StringSlice> text) { return "slice"; }
string Pick(Optional<ReadOnlySlice<char>> text) { return "chars"; }
Error<int[]> Load(bool ok)
{
    if (!ok)
        return error("missing");
    return [10, 20, 30];
}
string Read(Error<ReadOnlySlice<int>> values)
{
    if (values is ReadOnlySlice<int> v)
        return "read " + v.Length.ToString();
    if (values is error e)
        return e.Message;
    return "";
}
Error<Optional<ReadOnlySlice<uint16>>> Nested(bool ok)
{
    return Find(ok);
}
FileError<string> Open(bool ok)
{
    if (!ok)
        return error("denied", FileError.Denied);
    return "abc";
}
FileError<StringSlice> OpenView(bool ok)
{
    return Open(ok);
}
Error<StringSlice> Widened()
{
    Error<string> failed = error("widened", 404);
    return failed;
}

int Main()
{
    Console.WriteLine(Sum(Find(true)) + " " + Sum(Find(false)));

    Optional<string> word = "hello";
    Console.WriteLine(Text(word) + " " + Chars(word) + " " + Pick(word));

    int[] numbers = [10, 20, 30];
    Optional<Slice<int>> part = numbers[1..];
    Optional<ReadOnlySlice<int>> view = part;
    string line = "";
    if (view is ReadOnlySlice<int> r)
        line = "view " + r[1].ToString();
    Console.WriteLine(line + " " + Read(Load(true)) + " " + Read(Load(false)));

    line = "";
    if (Nested(true) is Optional<ReadOnlySlice<uint16>> o && o is ReadOnlySlice<uint16> n)
        line = "nested " + (n[0] + n[1] + n[2] + n[2]).ToString();
    if (Nested(false) is Optional<ReadOnlySlice<uint16>> empty && empty == null)
        line += " nested none";
    Console.WriteLine(line);

    line = "";
    if (OpenView(true) is StringSlice s)
        line = "coded " + s;
    if (OpenView(false) is error e)
        line += " failed " + e.Message + " " + (e.Code == FileError.Denied).ToString();
    if (Widened() is error w)
        line += " " + w.Message + " " + w.Code.ToString();
    Console.WriteLine(line);
    return 0;
}
