// Code labels of an Error<T, E> must cover every code, unless 'case error e', 'case E code' or 'default:' takes the rest.
// expect-error: the switch over the error codes of 'Error<int32, IoError>' does not handle 'Denied', 'Busy'; add the cases or 'default:'

using System;

error IoError { NotFound, Denied, Busy }

IoError<int> Open()
{
    return error(IoError.Busy);
}

int Main()
{
    switch (Open())
    {
        case int handle:
            return 0;
        case IoError.NotFound:
            return 1;
    }
    return 2;
}
