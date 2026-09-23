// A 'thread' function parameter must be a plain value type or SharedPtr<T> - not a string, array, container,
// Error<T>, raw pointer or Action/Func (their reference counts, or aliasing, are not safe to share across
// threads without the atomic reference counting SharedPtr<T> has).
// expect-error: must be a plain value type or SharedPtr<T>

using System;

thread void Bad(string s)
{
    Console.WriteLine(s);
}

void Main()
{
    Bad("hi").Join();
}
