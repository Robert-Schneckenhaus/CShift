// A lambda has no type of its own; it needs an Action/Func type to be converted to.
// expect-error: cannot infer the type of 'f' from a lambda; declare it with its Action/Func type

int Main()
{
    var f = (int x) => x + 1;
    return 0;
}
