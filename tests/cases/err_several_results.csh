// Errors with Error<T>, Optional<T>, 'is', 'try', error literals and casts, all in one run.
// expect-error: err_several_results.csh:14:31: error: cannot implicitly convert 'string' to 'int32'
// expect-error: err_several_results.csh:20:13: error: 'try' can only be used in a function that returns Error<T>
// expect-error: err_several_results.csh:27:18: error: 'is error' needs an Error<T> value, not 'Optional<int32>'
// expect-error: err_several_results.csh:29:18: error: pattern type 'string' does not match the payload type 'int32' of 'Optional<int32>'
// expect-error: err_several_results.csh:32:15: error: 'is' can only be used with Error<T>, Optional<T> and Thread<T> values, not 'int32'
// expect-error: err_several_results.csh:34:17: error: cannot cast 'int32' to 'bool'

using System;

Error<int> Parse(string text)
{
    if (text.Length == 0)
        return error("empty", "no code");
    return text.Length;
}

int Twice(string text)
{
    int n = try Parse(text);
    return n * 2;
}

int Main()
{
    Optional<int> maybe = 3;
    if (maybe is error e)
        return 1;
    if (maybe is string s)
        return 2;
    int count = 5;
    if (count is int c)
        return 3;
    bool flag = (bool)count;
    var result = Parse("12");
    if (result is int value)
        return value;
    return 0;
}
