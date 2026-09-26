// The file name must be a string literal (the file is read when the program is compiled).
// expect-error: embed needs a file name as a string literal: embed("file.txt")

const string Name = "embed/empty.txt";
const string Text = embed(Name);

int Main()
{
    return 0;
}
