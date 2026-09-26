// Error<void> is not a condition either; 'if (r)' must be written as '!(r is error)' or 'r is error e'.
// expect-error: 'Error<void>' cannot be used as a condition; test it with 'is error e' (failed)

using System;

Error<void> Save(bool ok)
{
    if (!ok)
        return error("cannot save");
    return;
}

int Main()
{
    if (Save(true))
        return 0;
    return 1;
}
