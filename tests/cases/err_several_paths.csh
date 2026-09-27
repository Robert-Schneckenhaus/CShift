// Missing returns and fall-through between switch sections, together with other errors, all in one run.
// expect-error: err_several_paths.csh:9:5: error: not all code paths of 'Sign' return a value
// expect-error: err_several_paths.csh:17:5: error: not all code paths of 'Loop' return a value
// expect-error: err_several_paths.csh:37:5: error: control cannot fall through from one case label to another (missing 'break')
// expect-error: err_several_paths.csh:48:16: error: cannot implicitly convert 'int32' to 'string'

using System;

int Sign(int x)
{
    if (x > 0)
        return 1;
    else if (x < 0)
        return -1;
}

int Loop(int x)
{
    while (true)
    {
        if (x > 3)
            break;
        x += 1;
    }
}

int Forever(int x)
{
    while (true)
        x += 1;
}

int Pick(int x)
{
    switch (x)
    {
    case 1:
        Console.WriteLine("one");
    case 2:
        return 2;
    default:
        return 0;
    }
}

int Main()
{
    string s = 5;
    return Sign(1) + Loop(0) + Forever(0) + Pick(1);
}
