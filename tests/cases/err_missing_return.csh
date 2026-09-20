// expect-error: not all code paths
int Pick(bool b)
{
    if (b)
        return 1;
}

int Main()
{
    return Pick(true);
}
