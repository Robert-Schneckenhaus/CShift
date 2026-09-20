// Environment.Exit ends the program with the given exit code; buffered output is flushed.
// expect-exit: 7
// expect-stdout: before exit
// arc-ignore
int Main()
{
    Console.WriteLine("before exit");
    Environment.Exit(7);
    Console.WriteLine("not reached");
    return 0;
}
