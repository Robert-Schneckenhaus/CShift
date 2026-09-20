// expect-exit: 101
// expect-stderr: panic: negative array length
int Main()
{
    int n = -5;
    var a = new int[n];
    return a.Length;
}
