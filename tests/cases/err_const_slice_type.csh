// A constant cannot be a writable Slice<T>: its elements could be changed.
// expect-error: a constant cannot be 'Slice<int32>' (its elements could be changed); use 'const ReadOnlySlice<int32>'

const Slice<int> Values = [1, 2, 3];

int Main()
{
    return 0;
}
