// Multiplications by constants (the 68000 backend writes them as mulu.w of the 16-bit halves): the low 32 bits of the
// product, for constants with and without a high half, for unsigned and signed values.
// expect-stdout: 2678602880 425371665
using System;

int Main()
{
    uint32[] xs = [0u, 1u, 2u, 65535u, 65536u, 123456789u, 4294967295u, 2147483648u, 3000000000u];
    uint32 acc = 0;
    foreach (var x in xs)
    {
        for (var round = 0; round < 8; round += 1)
            acc = unchecked(acc * 33u + x * 2654435769u + x * 31u + x * 65537u + x * 4294967295u);
    }
    int y = 12345;
    int z = unchecked(y * -7 + y * 100000 + y * -65536);
    Console.WriteLine(acc.ToString() + " " + z.ToString());
    return 0;
}
