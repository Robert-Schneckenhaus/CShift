// "platforms" in cshift.json: entries that only apply to the platform the program is built for.
using System;
using Plat from "../native/platform.h";

int Main()
{
    int expected = Process.IsWindows() ? 1 : (File.Exists("/System/Library/CoreServices/SystemVersion.plist") ? 3 : 2);
    if (Plat.CURRENT_PLATFORM == expected)
        Console.WriteLine("platform ok");
    else
        Console.WriteLine("wrong platform " + Plat.CURRENT_PLATFORM.ToString());
    return 0;
}
