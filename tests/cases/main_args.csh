// Main(string[] args): without command line arguments the array is empty
// expect-stdout: args: 0
int Main(string[] args)
{
    Console.WriteLine("args: " + args.Length.ToString());
    foreach (var a in args)
        Console.WriteLine(a);
    return args.Length;
}
