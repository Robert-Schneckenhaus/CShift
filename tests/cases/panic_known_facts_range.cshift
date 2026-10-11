// (x & 0x7fffffff) can be int.MaxValue: adding 1 stays checked.
// expect-exit: 101
// expect-stderr: panic: integer overflow
int Main()
{
    int x = -1;
    int y = (x & 0x7fffffff) + 1;
    return y;
}
