// expect-error: an explicit cast is required
int Main()
{
    int64 big = 5;
    int small = big;
    return small;
}
