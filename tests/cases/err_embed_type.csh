// embed gives a string.
// expect-error: embed(...) gives a string, so the constant must be 'const string', not 'int32'

const int Size = embed("embed/empty.txt");

int Main()
{
    return 0;
}
