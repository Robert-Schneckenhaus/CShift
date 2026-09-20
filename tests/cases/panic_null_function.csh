// expect-exit: 101
// expect-stderr: panic: call of a null function
int Main()
{
    Func<int, int> f = null;
    return f(1);
}
