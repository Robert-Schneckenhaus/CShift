// The bytes of files come one file per constant: a constant slice cannot contain slices.
// expect-error: embed("embed/*.txt") as 'ReadOnlySlice<uint8>' reads one file, without '*' or '?' (a constant slice cannot contain slices)

const ReadOnlySlice<uint8> Files = embed("embed/*.txt");

int Main()
{
    return 0;
}
