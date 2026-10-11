// uint32 + uint8 is computed in uint32 (like in C#), so its overflow is checked there.
// expect-exit: 101
// expect-stderr: panic: integer overflow
int Main()
{
    uint32 u = uint32.MaxValue;
    uint8 b = 1;
    var x = u + b;
    return (int)(x & 1u);
}
