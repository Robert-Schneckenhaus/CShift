// embed gives a string.
// expect-error: embed("embed/empty.txt") gives a string, so the constant must be 'const string' (or 'const ReadOnlySlice<uint8>' for its bytes), not 'int32'

const int Size = embed("embed/empty.txt");

int Main()
{
    return 0;
}
