// A constant slice holds plain constants, not other slices.
// expect-error: a constant slice cannot contain slices

const ReadOnlySlice<int> A = [1];
const ReadOnlySlice<int> B = [A, 2];

int Main()
{
    return 0;
}
