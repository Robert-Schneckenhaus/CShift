// expect-error: has the signature Func<int32, int32, int32>
int Add(int a, int b)
{
    return a + b;
}

int Main()
{
    Func<int, int> f = Add;
    return f(1);
}
