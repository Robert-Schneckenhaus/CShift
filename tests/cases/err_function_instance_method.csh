// expect-error: is an instance method; only static methods and free functions can be function values
struct Counter
{
    int Value;

    int Next(int step)
    {
        return Value + step;
    }
}

int Main()
{
    Func<int, int> f = Counter.Next;
    return f(1);
}
