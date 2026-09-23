// A 'thread' function may not touch global state, even through a function it calls.
// expect-error: a thread can only see its parameters and return value

using System;

int counter = 0;

void Bump()
{
    counter += 1;
}

thread void Bad()
{
    Bump();
}

void Main()
{
    Bad().Join();
}
