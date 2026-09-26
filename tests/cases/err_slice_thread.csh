// A slice cannot be passed to a thread: it refers to a block whose reference count is not atomic.
// expect-error: a 'thread' function parameter must be a value type, a string or a SharedPtr<T> of a thread-safe type, not 'StringSlice' (parameter 'text')

using System;

thread int Count(StringSlice text)
{
    return text.Length;
}

int Main()
{
    string s = "hello";
    var t = start Count(s[1..]);
    return t.Join();
}
