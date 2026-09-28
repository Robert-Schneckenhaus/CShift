// Errors in switch labels and sections, all in one run.
// expect-error: err_several_switch.csh:21:5: error: cannot implicitly convert 'string' to 'Mode'
// expect-error: err_several_switch.csh:25:5: error: the switch already has a 'default' label
// expect-error: err_several_switch.csh:34:5: error: 'bool' is not a member of union 'Shape'
// expect-error: err_several_switch.csh:32:31: error: undefined name 'missing'
// expect-error: err_several_switch.csh:37:5: error: the switch over enum 'Mode' does not handle 'On'; add the case or 'default:'

using System;

enum Mode : uint8 { Off, On }

union Shape { int, string }

int Main()
{
    Mode m = Mode.On;
    switch (m)
    {
    case Mode.Off:
        break;
    case "on":
        break;
    default:
        break;
    default:
        break;
    }
    Shape s = 3;
    switch (s)
    {
    case int n:
        Console.WriteLine(n + missing);
        break;
    case bool b:
        break;
    }
    switch (m)
    {
    case Mode.Off:
        break;
    }
    return 0;
}
