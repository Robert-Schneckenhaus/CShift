// embed_lines reads one file; several files are embed("*.txt").
// expect-error: embed_lines reads one file, without '*' or '?' (the contents of several files: embed("embed/*.txt"))

const ReadOnlySlice<string> Lines = embed_lines("embed/*.txt");

int Main()
{
    return 0;
}
