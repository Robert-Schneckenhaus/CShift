// expect-exit: 101
// expect-stderr: panic: array index out of range
int Main()
{
    var a = new int[3];
    int i = -1;
    return a[i];
}
