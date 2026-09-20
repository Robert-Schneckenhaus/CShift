// nint / nuint: integers with the size of a pointer (like IntPtr in C#).
// expect-stdout: nint ok

int Main()
{
    // Size follows the target (8 bytes on 64-bit targets)
    if (sizeof(nint) != sizeof(void*) || sizeof(nuint) != sizeof(void*))
        return 1;

    // Implicit conversions: 32-bit and smaller widen to nint/nuint
    int small = -5;
    nint n = small;
    if (n != -5)
        return 2;
    uint32 u = 4000000000u;
    nuint m = u;
    if (m != 4000000000)
        return 3;

    // Arithmetic stays in the native width
    nint big = 3000000000;
    big = big * 2;
    if (big != 6000000000 && sizeof(nint) == 8)
        return 4;

    // Explicit casts
    int back = (int)n;
    if (back != -5)
        return 5;
    nuint fromInt = (nuint)7;
    if (fromInt + 1 != 8)
        return 6;

    // nint widens to int64 implicitly (the other direction needs a cast: it can lose bits on 32-bit targets)
    int64 wide = 1;
    int64 sum = n + wide;
    if (sum != -4)
        return 7;

    // Checked arithmetic also applies to nint
    Console.WriteLine("nint ok");
    return 0;
}
