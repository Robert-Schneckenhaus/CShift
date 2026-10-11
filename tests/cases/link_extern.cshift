// The "link" directive passes a library to the linker
// (libm exists on all C toolchains except MSVC, where it is part of the CRT).
// expect-stdout: 3
link "m"

extern "C" double floor(double x);

int Main()
{
    double v = floor(3.7);
    Console.WriteLine((int)v);
    return 0;
}
