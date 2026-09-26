// A control statement as the body of another one needs braces: 'if (a) if (b) F();' is an error ('else if' is fine).
// expect-error: a nested 'if' needs braces: the body of 'if' must be a block '{ ... }' when it is a control statement

using System;

int Main()
{
    bool a = true;
    bool b = false;
    if (a)
        Console.WriteLine("one-line bodies are fine");
    else if (b)
        Console.WriteLine("and so are 'else if' chains");
    if (a)
        if (b)
            return 1;
    return 0;
}
