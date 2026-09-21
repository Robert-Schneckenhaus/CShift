// expect-error: must be a constant expression
int Main()
{
    int x = 3;
    const int Value = x + 1;
    return Value;
}
