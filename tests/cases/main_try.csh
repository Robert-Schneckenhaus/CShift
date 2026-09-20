// "try" inside "int Main", as in the example program of the language concept:
// on an error the message is printed and the program exits with code 1.
// expect-exit: 1
// expect-stdout: content of a.txt
// expect-stderr: error: empty path
Error<string> Load(string path)
{
    if (path.Length == 0)
        return error("empty path");
    return "content of " + path;
}

int Main()
{
    var first = try Load("a.txt");
    Console.WriteLine(first);
    var second = try Load("");
    Console.WriteLine("not reached");
    return 0;
}
