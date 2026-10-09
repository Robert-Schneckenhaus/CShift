// The value of '??=' is a T or an Optional<T>.
// expect-error: the right side of '??=' must be of type 'string' or 'Optional<string>', not 'int32'
int Main()
{
    Optional<string> name = null;
    name ??= 5;
    return 0;
}
