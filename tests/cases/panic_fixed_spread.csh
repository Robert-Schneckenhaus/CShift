// expect-exit: 101
// expect-stderr: panic: the collection for 'Fixed<int32, 2>' does not have 2 elements
// arc-ignore
// With spreads, the number of elements of a collection for a Fixed<T, N> is checked when the program runs.
int Main()
{
    int[] more = [1, 2, 3];
    Fixed<int, 2> values = [..more];
    return values[0];
}
