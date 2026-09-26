// embed only initializes a string constant; it does not exist at run time.
// expect-error: embed(...) can only be the whole initializer of a string constant: const string Text = embed("file.txt");

int Main()
{
    string text = embed("embed/empty.txt");
    return text.Length;
}
