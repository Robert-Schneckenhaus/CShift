// Console.ReadLine: the lines of the standard input without their line breaks, null at its end.
// stdin: first line
// stdin: second line
// stdin: über
// expect-stdout: Name? [first line]
// expect-stdout: [second line]
// expect-stdout: [über]
// expect-stdout: 3 lines
int Main()
{
    Console.Write("Name? ");
    int count = 0;
    while (Console.ReadLine() is string line)
    {
        count += 1;
        Console.WriteLine("[" + line + "]");
    }
    if (Console.ReadLine() is not null)
        Console.WriteLine("more than the input");
    Console.WriteLine(count.ToString() + " lines");
    return 0;
}
