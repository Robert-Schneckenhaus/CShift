// Copying out of a view is explicit, and a slice does not convert to a string by itself.
// expect-error: cannot implicitly convert 'StringSlice' to 'string' (a slice is a view; copy it with .ToString())

using System;

int Main()
{
    string s = "hello";
    string h = s[..2];
    return h.Length;
}
