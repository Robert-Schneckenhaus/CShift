// The checker reports every error of a program in one run, not only the first one: each mistake gives one message,
// and an expression with an error does not cause further messages.
// expect-error: err_several_errors.csh:16:17: error: undefined name 'cuont'
// expect-error: err_several_errors.csh:17:17: error: cannot implicitly convert 'string' to 'int32'
// expect-error: err_several_errors.csh:18:9: error: a condition must be of type 'bool', not 'int32'
// expect-error: err_several_errors.csh:25:18: error: cannot implicitly convert 'float64' to 'int32' (an explicit cast is required)
// expect-error: err_several_errors.csh:30:5: error: 'break' is only allowed inside a loop or switch
// expect-error: err_several_errors.csh:35:9: error: no matching function for call 'Half(string)': argument 1: cannot convert 'string' to 'int32'
// expect-error: err_several_errors.csh:36:10: error: undefined function 'Twice'
// expect-error: err_several_errors.csh:37:16: error: operator '-' cannot be applied to 'string' and 'int32'

int Count(int[] items)
{
    int total = 0;
    foreach (var item in items)
        total = cuont + item;          // undefined name; the '+' with it is not reported again
    int limit = "ten";
    if (total)
        return 1;
    return total;
}

int Half(int value)
{
    return value / 2.0;
}

void Loop()
{
    break;
}

int Main()
{
    Half("x");
    Twice(3);
    return "a" - 1;
}
