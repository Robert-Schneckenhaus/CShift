// A slice range of a constant slice is checked at compile time.
// expect-error: slice range 2..5 is out of bounds (the constant slice has 3 elements)

const ReadOnlySlice<int> Values = [1, 2, 3];
const ReadOnlySlice<int> Part = Values[2..5];

int Main()
{
    return 0;
}
