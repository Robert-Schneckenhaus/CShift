// A struct can only be iterated with foreach if it has Count() and Get(int).
// expect-error: needs the methods 'int Count()' and 'T Get(int index)'
struct Plain
{
    int X;
}

int Main()
{
    var p = new Plain();
    foreach (var x in p)
        return x;
    return 0;
}
