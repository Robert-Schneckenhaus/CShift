// expect-error: cannot assign to a read-only value
int Main()
{
    const int Value = 1;
    Value = 2;
    return Value;
}
