// Only bool may be used as a condition (no implicit conversion from integers).
// expect-error: a condition must be of type 'bool'
int Main()
{
    int x = 1;
    if (x)
        return 1;
    return 0;
}
