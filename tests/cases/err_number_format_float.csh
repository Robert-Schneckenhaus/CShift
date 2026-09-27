// D, X and B are only for integers.
// expect-error: the number format 'X' is only for integers

int Main()
{
    double d = 2.0;
    return $"{d:X}".Length;
}
