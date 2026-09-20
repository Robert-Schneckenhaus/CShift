// expect-exit: 101
// expect-stderr: panic: integer overflow
int Main()
{
    int m = int.MinValue;
    int d = -1;
    return m / d;
}
