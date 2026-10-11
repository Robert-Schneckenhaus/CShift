// An error enum is not a result value: Error<FileError> would read like a failure.
// expect-error: an error enum cannot be the value of a result (Error<FileError>); did you mean FileError<T> (Error<T, FileError>)?

using System;

error FileError
{
    NotFound,
    Denied = 13
}

Error<FileError> Last()
{
    return FileError.NotFound;
}

int Main()
{
    return 0;
}
