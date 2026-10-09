// '??' needs an Optional<T> on its left.
// expect-error: the left side of '??' must be an Optional<T>, not 'int32'
int Main()
{
    int x = 1;
    return x ?? 2;
}
