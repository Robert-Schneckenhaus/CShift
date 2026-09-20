// Error<Optional<T>>, Optional<Error<T>>, ... are not allowed.
// expect-error: cannot be nested
Error<Optional<int>> Broken()
{
    return null;
}

int Main()
{
    return 0;
}
