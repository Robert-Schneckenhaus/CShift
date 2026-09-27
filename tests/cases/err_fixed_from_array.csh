// A heap array never turns into a Fixed<T, N> by itself.
// expect-error: (copy the elements into the Fixed with a collection expression: [..values])

int Main()
{
    int[] b = [1];
    Fixed<int, 1> a = b;
    return a[0];
}
