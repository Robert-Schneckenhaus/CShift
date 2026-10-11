// Error<T> is not a condition: '!r' would hide whether it asks "did it fail?". 'r is error e' says it.
// expect-error: 'Error<int32>' cannot be used as a condition; test it with 'is error e' (failed) or 'is int32 v' (succeeded)

using System;

Error<int> Parse(string text)
{
    if (text.Length == 0)
        return error("empty");
    return text.Length;
}

int Main()
{
    var r = Parse("");
    if (!r)
        return 1;
    return 0;
}
