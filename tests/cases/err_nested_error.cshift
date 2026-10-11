// Optional<Error<T>>, Error<Error<T>>, Optional<Optional<T>> are not allowed (only Error<Optional<T>> is).
// expect-error: cannot be nested

Optional<Error<int>> Broken()
{
    return null;
}

int Main()
{
    return 0;
}
