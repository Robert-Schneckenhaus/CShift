// expect-exit: 101
// expect-stderr: panic: slice range out of bounds
// arc-ignore
// A slice range outside the array (here: end past the length) panics like an index out of range.
int Main()
{
    int[] a = new int[] { 1, 2, 3 };
    int end = 5;
    var s = a[1..end];
    return s.Length;
}
