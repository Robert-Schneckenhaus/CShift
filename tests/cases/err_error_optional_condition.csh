// Error<Optional<T>> cannot be tested as a bool ('if (x)', '!x'): it would be unclear whether that asks "did it
// succeed?" or "was something found?". 'x is T v' and 'x is Optional<T> o' say it explicitly.
// expect-error: cannot be used as a condition: it is unclear whether it asks for success or for a value; write 'x is int32 v'

using System;

Error<Optional<int>> Find(int key)
{
    if (key < 0)
        return error("negative key");
    return null;
}

int Main()
{
    var r = Find(1);
    if (!r)
        return 1;
    return 0;
}
