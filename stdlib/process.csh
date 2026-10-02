namespace System;

extern "C" int system(char* command);
extern "C" char* getenv(char* name);
extern "C" void* popen(char* command, char* mode);
extern "C" int pclose(void* stream);

using System.Native;

/// Runs other programs and reads environment variables (static functions).
///
/// ```
/// int code = Process.Run("clang -c a.c -o a.o");
/// var text = Process.RunCapture("clang --version");   // the text the program writes to stdout
/// ```
struct Process
{
    /// Runs a command line through the system shell (`sh` or `cmd.exe`) and waits for it.
    /// @returns the exit code of the program, or -1 if it could not be started.
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

    /// True on Windows. The environment variable OS is not always passed on (e.g. by an MSYS2 login shell), so the
    /// system's cmd.exe is looked for as well.
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

    /// Runs a command line through the system shell and returns everything the program writes to stdout.
    /// @returns nothing (`null`) if the program could not be started.
    static Optional<string> RunCapture(string command)
    {
        var sb = StringBuilder.Create();
        unsafe
        {
            string line = command;
            if (IsWindows())
                line = "\"" + command + "\""; // cmd.exe strips the outer quotes
            void* pipe = popen(line.CStr(), "r".CStr());
            if (pipe == null)
                return null;
            uint8* buffer = (uint8*)Memory.Allocate(4096);
            while (true)
            {
                nuint n = fread(buffer, 1, 4096, pipe);
                if (n == 0)
                    break;
                for (var i = 0; i < (int)n; i += 1)
                    sb.Append((char)buffer[i]);
            }
            Memory.Free(buffer);
            pclose(pipe);
        }
        return sb.ToString();
    }

    /// The value of the environment variable `name`.
    /// @returns nothing (`null`) if it is not set.
    static Optional<string> GetEnv(string name)
    {
        unsafe
        {
            char* value = getenv(name.CStr());
            if (value == null)
                return null;
            return string.FromCStr(value);
        }
    }
}
