// Console.WriteError / WriteErrorLine write to stderr
// expect-stderr: to stderr
// expect-stdout: to stdout
int Main()
{
    Console.WriteErrorLine("to stderr");
    Console.WriteError("also ");
    Console.WriteErrorLine("stderr");
    Console.WriteLine("to stdout");
    return 0;
}
