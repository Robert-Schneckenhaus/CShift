// y < 10 with y = x + 5 says nothing about x + 6 when the sum wrapped around (unchecked): it stays checked.
// expect-exit: 101
// expect-stderr: panic: integer overflow
int Main()
{
    int x = int.MaxValue - 2;
    int y = unchecked(x + 5);
    if (y < 10)
        return x + 6;
    return 0;
}
