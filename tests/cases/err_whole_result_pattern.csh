// A pattern of the value's own type would always match, so it is not allowed.
// expect-error: a pattern of the value's own type ('Error<int32>') would always match; test for a failure with 'is error e' or for a value with 'is int32 v'

Error<int> Parse(string text)
{
    return 1;
}

int Main()
{
    if (Parse("1") is Error<int> r)
        return 1;
    return 0;
}
