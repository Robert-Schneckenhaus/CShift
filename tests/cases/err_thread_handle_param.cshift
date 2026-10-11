// A Thread<T> handle holds a SharedPtr to the result, so it can only be passed to another thread if T is thread-safe.
// expect-error: not 'System.Thread<string>' (parameter 'other') ('string' is reference-counted

using System;

thread string Name()
{
    return "worker";
}

thread int Wait(Thread<string> other)
{
    return other.Join().Length;
}

void Main()
{
    (start Wait(start Name())).Join();
}
