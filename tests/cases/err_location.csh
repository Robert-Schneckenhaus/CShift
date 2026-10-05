// Where errors point: a value that does not convert at its start (not at the '(' of a call or the '.' of a member), a
// call that does not resolve at the function's name, a missing member at its name.
// expect-error: err_location.csh:19:14: error: cannot implicitly convert 'int32' to 'char' (an explicit cast is required)
// expect-error: err_location.csh:20:16: error: cannot implicitly convert 'StringSlice' to 'string' (a slice is a view; copy it with .ToString())
// expect-error: err_location.csh:21:16: error: cannot implicitly convert 'int32' to 'string'
// expect-error: err_location.csh:22:17: error: no matching function for call 'Bar(string)'
// expect-error: err_location.csh:23:32: error: struct 'Pair' has no field 'Third'
// expect-error: err_location.csh:24:12: error: cannot implicitly convert 'bool' to 'int32'
struct Pair { int First; int Second; }

int Bar(char c)
{
    return (int)c + 1;
}

int Main()
{
    char[] foo = new char[4];
    foo[0] = Bar(foo[0]);
    string s = " a ".Trim();
    string t = foo.Length + 1;
    int u = 1 + Bar("x");
    int v = Pair { First = 1 }.Third;
    return foo.Length > 2;
}
