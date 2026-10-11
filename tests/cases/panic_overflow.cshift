// Checked arithmetic: overflow terminates the program with a panic.
// expect-exit: 101
// expect-stderr: panic: integer overflow
int Main()
{
    int x = int.MaxValue;
    x += 1;
    return x;
}
