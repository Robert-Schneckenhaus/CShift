// embed is the whole initializer, not part of a constant expression.
// expect-error: embed(...), embed_filenames(...) and embed_lines(...) can only be the whole initializer of a constant

const string Text = "x" + embed("embed/empty.txt");

int Main()
{
    return 0;
}
