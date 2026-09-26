// A constant slice can only spread other constant slices.
// expect-error: must be a constant expression

int Main()
{
    int[] a = [1, 2];
    const ReadOnlySlice<int> Values = [..a, 3];
    return 0;
}
