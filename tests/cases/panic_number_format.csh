// A format that is only known at run time is checked when it is used.
// expect-exit: 101
// expect-stderr: panic: invalid number format 'Q' for an integer
// expect-stderr:   called from
// expect-stderr: panic_number_format.csh:14:22 in Main
// arc-ignore

using System;

int Main()
{
    string format = "Q";
    int n = 5;
    return n.ToString(format).Length;
}
