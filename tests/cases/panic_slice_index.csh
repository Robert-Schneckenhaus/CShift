// expect-exit: 101
// expect-stderr: panic: slice index out of range
// arc-ignore
// An index into a slice is checked against the slice, not against the whole array.
int Main()
{
    int[] a = new int[] { 1, 2, 3, 4 };
    var s = a[..2];
    int i = 2;
    return s[i];
}
