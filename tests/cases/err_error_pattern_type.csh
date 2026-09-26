// 'is error' only works on Error<T>.
// expect-error: 'is error' needs an Error<T> value, not 'Optional<int32>'

int Main()
{
    Optional<int> o = null;
    if (o is error e)
        return 1;
    return 0;
}
