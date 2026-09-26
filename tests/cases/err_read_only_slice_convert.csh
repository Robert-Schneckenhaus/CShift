// A ReadOnlySlice never becomes a writable Slice<T> or an array by itself.
// expect-error: cannot implicitly convert 'ReadOnlySlice<int32>' to 'Slice<int32>' (a ReadOnlySlice cannot become writable; copy it with .ToArray())

int Main()
{
    int[] a = [1, 2];
    ReadOnlySlice<int> view = a;
    Slice<int> s = view;
    return s.Length;
}
