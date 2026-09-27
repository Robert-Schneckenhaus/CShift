// A constant index into a Fixed<T, N> is checked when the program is compiled.
// expect-error: index 16 is out of range for 'Fixed<int32, 16>' (16 elements)

int Main()
{
    Fixed<int, 16> a;
    return a[16];
}
