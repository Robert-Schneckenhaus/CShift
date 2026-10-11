// An Error<T> is not an Optional<T>: what went wrong would be dropped without a word.
// expect-error: the left side of '??' must be an Optional<T>, not 'Error<int32, System.ParseError>' (an Error<T> says why it has no value
using System;

int Main()
{
    return "12".ParseInt() ?? 0;
}
