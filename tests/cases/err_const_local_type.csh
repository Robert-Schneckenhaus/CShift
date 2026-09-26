// expect-error: a constant cannot be 'int32[]' (its elements could be changed); use 'const ReadOnlySlice<int32>'
int Main()
{
    const int[] Values = new int[3];
    return 0;
}
