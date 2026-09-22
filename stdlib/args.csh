// Command line arguments for 'int Main(string[] args)'.

namespace System.Native;

// Called by the generated entry point: builds the argument array from C's argc/argv. The program name
// (argv[0]) is not part of it, like in C#.
string[] MakeArgs(int argc, char** argv)
{
    int count = argc > 1 ? argc - 1 : 0;
    var result = new string[count];
    unsafe
    {
        for (var i = 0; i < count; i += 1)
            result[i] = string.FromCStr((char*)argv[i + 1]);
    }
    return result;
}
