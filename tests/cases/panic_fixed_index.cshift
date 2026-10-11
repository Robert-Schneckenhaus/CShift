// expect-exit: 101
// expect-stderr: panic: fixed array index out of range
// arc-ignore
// An index into a Fixed<T, N> that is only known when the program runs is checked then.
int Main()
{
    Fixed<int, 4> values;
    int i = 4;
    return values[i];
}
