// expect-exit: 101
// expect-stderr: panic: array copy out of range
// arc-ignore
int Main()
{
    var a = new int[3];
    var b = new int[2];
    Array.Copy(a, 0, b, 0, 3);
    return 0;
}
