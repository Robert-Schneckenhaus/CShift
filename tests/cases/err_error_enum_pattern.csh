// 'is FileError code' needs a FileError<T>: the codes of a plain Error<T> are ints.
// expect-error: 'is FileError' needs an Error<T, FileError> value, not 'Error<int32>' (its codes are plain ints)

using System;

error FileError
{
    NotFound,
    Denied = 13
}

Error<int> Parse(string text)
{
    return text.Length;
}

int Main()
{
    if (Parse("") is FileError code)
        return 1;
    return 0;
}
