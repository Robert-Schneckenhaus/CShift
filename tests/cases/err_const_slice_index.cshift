// An index into a constant slice is checked at compile time.
// expect-error: index 4 is out of range (the constant slice has 3 elements)

const ReadOnlySlice<int> Values = [1, 2, 3];
const int Fourth = Values[4];

int Main()
{
    return 0;
}
