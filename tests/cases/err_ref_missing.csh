// A 'ref' parameter must be called with 'ref'.
// expect-error: pass it with 'ref'
void Inc(ref int x)
{
    x += 1;
}

int Main()
{
    int a = 1;
    Inc(a);
    return a;
}
