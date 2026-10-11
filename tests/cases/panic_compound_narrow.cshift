// A compound assignment whose result is wider than the target is narrowed; in checked code a value that does not fit
// is an overflow (with --unchecked it wraps around).
// expect-exit: 101
// expect-stderr: panic: integer overflow
int Main()
{
    uint8 u = 250;
    int x = 100000;
    u += x;
    return u;
}
