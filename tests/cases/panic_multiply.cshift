// expect-exit: 101
// expect-stderr: panic: integer overflow
int64 Grow(int64 v)
{
    return v * 1000000;
}

int Main()
{
    int64 v = 1;
    for (var i = 0; i < 10; i += 1)
        v = Grow(v);
    return 0;
}
