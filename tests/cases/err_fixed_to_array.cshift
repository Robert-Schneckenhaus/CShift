// A Fixed<T, N> never turns into a heap array by itself.
// expect-error: (a Fixed<T, N> is a value stored inline; copy it into a heap array with .ToArray())

int Main()
{
    Fixed<int, 4> a;
    int[] b = a;
    return b.Length;
}
