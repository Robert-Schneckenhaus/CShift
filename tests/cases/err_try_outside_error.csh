// expect-error: 'try' can only be used in a function that returns Error<T>
Error<int> Parse()
{
    return 1;
}

void Run()
{
    var x = try Parse();
}

int Main()
{
    Run();
    return 0;
}
