// An error code cannot be 0: code 0 means "no specific code" (error("text"), a default result).
// expect-error: error code 'Ok' cannot be 0: code 0 means "no specific code" (error codes count from 1)

using System;

error FileError
{
    NotFound,
    Denied = 13
}

error Status
{
    Ok = 0,
    Failed
}

int Main()
{
    return 0;
}
