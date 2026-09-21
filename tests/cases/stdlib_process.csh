// Standard library: Process.Run returns the exit code of the command.
// expect-exit: 0

using System;

int Main()
{
    if (Process.Run("exit 0") != 0)
        return 1;
    if (Process.Run("exit 3") != 3)
        return 2;
    return 0;
}
