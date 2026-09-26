// 'try' passes an error on unchanged, so a plain Error<T> cannot flow into FileError<T>.
// expect-error: 'try' cannot pass on the error of 'Error<int32>' from a function that returns 'Error<int32, FileError>': its codes are not values of FileError; translate it: 'if (x is error e) return error(e.Message, FileError.Member);'

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

FileError<int> Load(string text)
{
    int n = try Parse(text);
    return n;
}

int Main()
{
    return 0;
}
