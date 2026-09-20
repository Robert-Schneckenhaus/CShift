// expect-error: a call of 'Func<int32, int32>' needs 1 argument(s), got 2
int Square(int x)
{
    return x * x;
}

int Main()
{
    Func<int, int> f = Square;
    return f(1, 2);
}
