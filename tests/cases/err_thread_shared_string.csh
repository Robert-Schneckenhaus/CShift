// A SharedPtr<T> is shared with the thread, so T must be thread-safe: SharedPtr<string> would copy the string's
// non-atomic reference count between threads.
// expect-error: ('string' is reference-counted without atomics and cannot be shared with another thread)

using System;

thread int Length(SharedPtr<string> text)
{
    return text.Get().Length;
}

void Main()
{
    (start Length(SharedPtr<string>.Create("abc"))).Join();
}
