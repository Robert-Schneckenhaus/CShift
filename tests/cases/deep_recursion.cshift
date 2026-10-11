// Deep recursion with a buffer on the stack in every call works: 2000 calls with 256 bytes each need more than the
// 64 KB of stack that wasm-ld gives a WebAssembly program by default (the driver asks for 8 MB).
// expect-stdout: depth 2000, sum 2001000
using System;

void Fill(ref Fixed<int, 64> buffer, int n)
{
    for (int i = 0; i < 64; i += 1)
        buffer[i] = n;
}

int64 Sum(int n)
{
    if (n == 0)
        return 0;
    Fixed<int, 64> buffer;
    Fill(ref buffer, n);
    return buffer[63] + Sum(n - 1);
}

void Main()
{
    Console.WriteLine($"depth 2000, sum {Sum(2000)}");
}
