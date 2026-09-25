// A 'thread' function parameter must be a value type, a string (copied for the thread) or a SharedPtr<T> of a
// thread-safe type - not an array, a container, a raw pointer or Action/Func: their reference counts (or aliasing)
// are not safe to share across threads.
// expect-error: must be a value type, a string or a SharedPtr<T> of a thread-safe type, not 'System.List<int32>' (parameter 'values')

using System;

thread int Bad(List<int> values)
{
    return values.Count();
}

void Main()
{
    (start Bad(List<int>.Create())).Join();
}
