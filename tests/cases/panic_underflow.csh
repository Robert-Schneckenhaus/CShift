// expect-exit: 101
// expect-stderr: panic: integer overflow
int Main()
{
    uint u = 0;
    u -= 1;
    return (int)u;
}
