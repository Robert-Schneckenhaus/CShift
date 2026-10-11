// A binding of 'is not' is not assigned in the 'if' branch (the pattern did not match there).
// expect-error: 'v' is not assigned here: 'x is not T v' assigns it only where the pattern matched (the 'else' branch, or after the 'if' when its branch returns, breaks or continues)

using System;

Error<int> Parse(string text)
{
    if (text.Length == 0)
        return error("empty");
    return text.Length;
}

int Main()
{
    if (Parse("") is not int v)
        Console.WriteLine("no number");
    return v;
}
