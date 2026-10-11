// A 'thread' function cannot be converted to Action/Func: calling it through a function pointer would just call
// it directly instead of spawning it.
// expect-error: cannot be used as a function pointer

using System;

thread void Foo(int x)
{
    Console.WriteLine(x);
}

void Main()
{
    Action<int> a = Foo;
    a(5);
}
