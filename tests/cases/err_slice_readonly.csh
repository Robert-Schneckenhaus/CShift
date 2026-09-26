// A StringSlice is read-only: strings are immutable, so their views are too.
// expect-error: a StringSlice is read-only (strings are immutable)

using System;

int Main()
{
    string s = "hello";
    StringSlice h = s[..2];
    h[0] = (char)72;
    return 0;
}
