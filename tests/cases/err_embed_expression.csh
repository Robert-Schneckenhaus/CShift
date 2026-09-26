// embed is the whole initializer, not part of a constant expression.
// expect-error: embed(...) can only be the whole initializer of a string constant

const string Text = "x" + embed("embed/empty.txt");

int Main()
{
    return 0;
}
