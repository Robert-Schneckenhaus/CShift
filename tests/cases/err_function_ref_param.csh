// expect-error: has ref parameters
void Bump(ref int x)
{
    x += 1;
}

int Main()
{
    Action<int> a = Bump;
    return 0;
}
