// memcpy, memmove and memset of the Amiga runtime against plain loops: every start (even/odd for source and
// destination), lengths around the tower size, overlapping moves in both directions.
using System;

extern "C" void* memcpy(void* dst, void* src, nuint n);
extern "C" void* memmove(void* dst, void* src, nuint n);
extern "C" void* memset(void* dst, int value, nuint n);

const ReadOnlySlice<int> Lengths = [0, 1, 2, 3, 4, 5, 7, 8, 15, 16, 17, 18, 19, 20, 31, 32, 33, 63, 64, 65, 66, 67, 68,
                                    79, 80, 127, 128, 129, 255, 256, 300, 513];
const int Size = 640;

int Main()
{
    var src = new uint8[Size];
    var dst = new uint8[Size];
    var expect = new uint8[Size];
    int errors = 0;
    int checks = 0;
    unsafe
    {
        foreach (var n in Lengths)
        {
            for (var s = 0; s < 4; s += 1)
            {
                for (var d = 0; d < 4; d += 1)
                {
                    // memcpy
                    for (var i = 0; i < Size; i += 1)
                    {
                        src[i] = (uint8)(i * 7 + n);
                        dst[i] = 238;
                        expect[i] = 238;
                    }
                    for (var i = 0; i < n; i += 1)
                        expect[d + i] = src[s + i];
                    void* r = memcpy(&dst[d], &src[s], (nuint)n);
                    for (var i = 0; i < Size; i += 1)
                    {
                        if (dst[i] != expect[i])
                            errors += 1;
                    }
                    if (r != (void*)&dst[d])
                        errors += 1000;
                    checks += 1;

                    // memset
                    for (var i = 0; i < Size; i += 1)
                    {
                        dst[i] = 238;
                        expect[i] = (uint8)(i >= d && i < d + n ? 165 : 238);
                    }
                    memset(&dst[d], 165 + 256 * s, (nuint)n);
                    for (var i = 0; i < Size; i += 1)
                    {
                        if (dst[i] != expect[i])
                            errors += 1;
                    }
                    checks += 1;

                    // memmove within one buffer, both directions
                    foreach (var shift in new int[] { 1, 2, 3, 5, 37 })
                    {
                        for (var dir = 0; dir < 2; dir += 1)
                        {
                            int from = dir == 0 ? s : s + shift;
                            int to = dir == 0 ? d + shift : d;
                            for (var i = 0; i < Size; i += 1)
                            {
                                dst[i] = (uint8)(i * 13 + n);
                                expect[i] = dst[i];
                            }
                            for (var i = 0; i < n; i += 1)
                                expect[to + i] = dst[from + i];
                            memmove(&dst[to], &dst[from], (nuint)n);
                            for (var i = 0; i < Size; i += 1)
                            {
                                if (dst[i] != expect[i])
                                    errors += 1;
                            }
                            checks += 1;
                        }
                    }
                }
            }
        }
    }
    Console.WriteLine("checks " + checks.ToString() + " errors " + errors.ToString());
    return errors == 0 ? 0 : 1;
}
