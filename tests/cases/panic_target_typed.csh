// Target-typed integer arithmetic is checked in the target type: 200 + 100 overflows uint8.
// expect-exit: 101
// expect-stderr: panic: integer overflow
// expect-stderr: panic_target_typed.csh:9:
int Main()
{
    uint8 a = 200;
    uint8 b = 100;
    uint8 r = a + b;
    return r;
}
