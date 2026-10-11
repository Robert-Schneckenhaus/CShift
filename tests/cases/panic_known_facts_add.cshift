// i < n only says that i + 1 cannot overflow, not i + 2.
// expect-exit: 101
// expect-stderr: panic: integer overflow
int Main()
{
    int n = int.MaxValue;
    int i = int.MaxValue - 1;
    if (i < n)
        return i + 2;
    return 0;
}
