// A result with typed codes (FileError<T>) only takes codes of its error enum, not an int code.
// expect-error: cannot implicitly convert 'error(int)' to 'Error<string, FileError>' (the error code must be a value of FileError: error("...", FileError.Member) or error(FileError.Member))

using System;

error FileError
{
    NotFound,
    Denied = 13
}

FileError<string> Read(string path)
{
    return error("cannot read " + path, 5);
}

int Main()
{
    return 0;
}
