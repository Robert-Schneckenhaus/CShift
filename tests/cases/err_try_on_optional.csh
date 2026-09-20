// try only works with Error<T>, not with Optional<T>.
// expect-error: 'try' can only be used with Error<T> values
Optional<int> Find()
{
    return 1;
}

Error<int> Run()
{
    var x = try Find();
    return x;
}

int Main()
{
    return 0;
}
