// try on an Error<void> yields no value.
// expect-error: cannot infer the type of 'x' from 'void'
Error<void> Work()
{
    return;
}

Error<int> Run()
{
    var x = try Work();
    return 1;
}

int Main()
{
    return 0;
}
