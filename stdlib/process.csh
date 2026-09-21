// Running other programs.
//
//     int code = Process.Run("clang -c a.c -o a.o");

namespace System;

extern "C" int system(char* command);
extern "C" char* getenv(char* name);

struct Process
{
    // Runs a command line through the system shell and waits for it. Returns the exit code of the program
    // (-1 if it could not be started).
    static int Run(string command)
    {
        int result = 0;
        unsafe
        {
            string line = command;
            if (IsWindows())
                line = "\"" + command + "\""; // cmd.exe strips the outer quotes
            result = system(line.CStr());
        }
        // POSIX systems return the wait status (exit code in the second byte)
        if (!IsWindows() && result > 255)
            result = result / 256;
        return result;
    }

    // True on Windows. The environment variable OS is not always passed on (e.g. by an MSYS2 login shell), so the
    // system's cmd.exe is looked for as well.
    static bool IsWindows()
    {
        unsafe
        {
            char* os = getenv("OS".CStr());
            if (os != null && string.FromCStr(os) == "Windows_NT")
                return true;
        }
        return File.Exists("C:\\Windows\\System32\\cmd.exe");
    }
}
