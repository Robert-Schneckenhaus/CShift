// Output written before a panic must still appear.
// expect-exit: 101
// expect-stdout: before
// expect-stderr: panic: division by zero
// arc-ignore
int Divide(int a, int b)
{
    return a / b;
}

int Main()
{
    Console.WriteLine("before");
    return Divide(1, 0);
}
