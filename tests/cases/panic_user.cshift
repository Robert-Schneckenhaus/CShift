// Environment.Panic terminates the program like a failed runtime check.
// expect-exit: 101
// expect-stderr: panic: something is wrong
// arc-ignore
int Main()
{
    int x = 1;
    if (x == 1)
        Environment.Panic("something is " + "wrong");
    return 0;
}
