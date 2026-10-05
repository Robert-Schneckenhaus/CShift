// Errors in methods, with fields, 'this' and calls of other methods; the rest of a statement with an error is still
// checked.
// expect-error: err_several_methods.csh:15:17: error: cannot implicitly convert 'bool' to 'int32'
// expect-error: err_several_methods.csh:22:7: error: struct 'Counter' has no method 'Reset'
// expect-error: err_several_methods.csh:23:12: error: undefined name 'stepp'
// expect-error: err_several_methods.csh:24:20: error: cannot assign to a read-only value (a constant or a 'const ref' parameter)
// expect-error: err_several_methods.csh:25:5: error: a void function cannot return a value

struct Counter
{
    int Value;

    int Next(int step)
    {
        Value = true;
        return Value + step;
    }
}

void Use(Counter c, const ref Counter fixedOne)
{
    c.Reset();
    c.Next(stepp);
    fixedOne.Value = 3;
    return 1;
}

int Main()
{
    return 0;
}
