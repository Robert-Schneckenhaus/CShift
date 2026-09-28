// A generic body is checked once, also if nothing instantiates it: its errors are reported with the others. What depends
// on a type parameter is checked when the body is instantiated.
// expect-error: err_several_generics.csh:21:47: error: undefined name 'missingName'
// expect-error: err_several_generics.csh:22:32: error: operator '*' cannot be applied to 'int32' and 'string'
// expect-error: err_several_generics.csh:28:18: error: cannot implicitly convert 'string' to 'int32'
// expect-error: err_several_generics.csh:34:23: error: undefined name 'undefinedThing'
// expect-error: err_several_generics.csh:37:5: error: not all code paths of 'NoReturn<T>' return a value

using System;

interface IShow
{
    string Show();
}

struct Box<T> where T : IShow
{
    T Value;
    int Count;

    string Describe() { return Value.Show() + missingName; }
    int Twice() { return Count * "2"; }
    T Get() { return Value; }
}

T Largest<T>(T a, T b) where T : IComparable<T>
{
    int unused = "x";
    return a.CompareTo(b) > 0 ? a : b;
}

void Never<T>(T x)
{
    Console.WriteLine(undefinedThing);
}

int NoReturn<T>(T x)
{
    int y = 1;
}

int Main()
{
    return Largest(1, 2);
}
