// expect-error: constants can only be numbers, bool, char, string or enum values
int Main()
{
    const int[] Values = new int[3];
    return 0;
}
