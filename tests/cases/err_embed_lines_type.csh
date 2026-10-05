// embed_lines gives the lines of the file: a ReadOnlySlice<string>, not a string.
// expect-error: embed_lines("embed/lines_open.txt") gives the lines of the file, so the constant must be 'const ReadOnlySlice<string>', not 'string'

const string Lines = embed_lines("embed/lines_open.txt");

int Main()
{
    return 0;
}
