// Errors in switch labels and sections, all in one run.
// expect-error: err_several_switch.csh:20:5: error: cannot implicitly convert 'string' to 'Mode'
// expect-error: err_several_switch.csh:24:5: error: the switch already has a 'default' label
// expect-error: err_several_switch.csh:33:5: error: 'bool' is not a member of union 'Shape'
// expect-error: err_several_switch.csh:31:31: error: undefined name 'missing'

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
    return 0;
}
