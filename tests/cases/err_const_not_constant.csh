// expect-error: must be a constant expression
int Compute()
{
    return 4;
}

const int Value = Compute();

int Main()
{
    return 0;
}
