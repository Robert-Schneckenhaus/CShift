// Optional<T> cannot be the condition of '?:'.
// expect-error: 'Optional<string>' cannot be used as a condition; test it with 'is string v' (has a value) or '== null' / '!= null'

using System;

Optional<string> Name(int id)
{
    if (id == 1)
        return "one";
    return null;
}

int Main()
{
    var n = Name(2);
    Console.WriteLine(n ? "found" : "missing");
    return 0;
}
