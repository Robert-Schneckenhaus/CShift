// expect-exit: 101
// expect-stderr: panic: the value must be positive
// expect-stderr: panic_custom_location.csh:11:26 in Check
// arc-ignore
// Environment.Panic shows where it was called, like the checks of the compiler.
using System;

void Check(int value)
{
    if (value < 0)
        Environment.Panic("the value must be positive");
}

int Main()
{
    Check(-1);
    return 0;
}
