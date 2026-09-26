// Returning an error code where the value is expected: it would be a success; write 'return error(FileError.X);'.
// expect-error: cannot implicitly convert 'FileError' to 'Error<int32>' (an error code is not a value: write 'return error(FileError.Member);')

using System;

error FileError
{
    NotFound,
    Denied = 13
}

Error<int> Size(string path)
{
    if (path.Length == 0)
        return FileError.NotFound;
    return 1;
}

int Main()
{
    return 0;
}
