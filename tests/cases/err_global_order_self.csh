// expect-error: a global cannot use itself in its own initializer
int Counter = Counter + 1;

int Main()
{
    return Counter;
}
