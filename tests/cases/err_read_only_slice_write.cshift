// A ReadOnlySlice cannot change its elements.
// expect-error: a ReadOnlySlice is read-only (use an array or a Slice<T> to change elements)

int Main()
{
    int[] a = [1, 2];
    ReadOnlySlice<int> view = a;
    view[0] = 5;
    return 0;
}
