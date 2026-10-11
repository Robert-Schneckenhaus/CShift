// The right side of '??' is a T or an Optional<T>.
// expect-error: the right side of '??' must be of type 'int32' or 'Optional<int32>', not 'string'
int Main()
{
    Optional<int> x = null;
    var y = x ?? "none";
    return 0;
}
