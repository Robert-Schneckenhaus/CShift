// Errors that the checker reports together (pointers, Fixed, using, unions, function values, lambdas, 'is not'):
// one run reports all of them.
// expect-error: err_several_checks.csh:45:15: error: cannot assign to a read-only value (a constant or a 'const ref' parameter)
// expect-error: err_several_checks.csh:51:14: error: taking an address is only allowed in an 'unsafe' context
// expect-error: err_several_checks.csh:53:15: error: index 4 is out of range for 'Fixed<int32, 4>' (4 elements)
// expect-error: err_several_checks.csh:54:5: error: 'using' requires a struct that implements IDisposable, but 'Plain' does not
// expect-error: err_several_checks.csh:56:14: error: 'string' is not a member of union 'Number'
// expect-error: err_several_checks.csh:58:33: error: cannot convert function 'Square' to 'Func<int32, int32, int32>': 'Square' has the signature Func<int32, int32>
// expect-error: err_several_checks.csh:59:24: error: cannot convert function 'Bump' to 'Action<int32>': 'Bump' has ref parameters or C conversions (string/struct marshalling) and cannot be used as a function pointer
// expect-error: err_several_checks.csh:61:13: error: a call of 'Func<int32, int32>' needs 1 argument(s), got 2
// expect-error: err_several_checks.csh:62:26: error: the lambda has 2 parameter(s), 'Func<int32, int32>' needs 1
// expect-error: err_several_checks.csh:63:29: error: parameter 't' of the lambda has type 'string', but 'Func<int32, int32>' needs 'int32'
// expect-error: err_several_checks.csh:64:5: error: cannot infer the type of 'any' from a lambda; declare it with its Action/Func type
// expect-error: err_several_checks.csh:66:32: error: cannot assign to 'count': a lambda gets a read-only copy of the variables it uses (return the new value instead)
// expect-error: err_several_checks.csh:69:12: error: 'v' is not assigned here: 'x is not T v' assigns it only where the pattern matched (the 'else' branch, or after the 'if' when its branch returns, breaks or continues)

using System;

struct Plain
{
    int X;
}

union Number { int, double }

int Square(int x)
{
    return x * x;
}

void Bump(ref int x)
{
    x += 1;
}

Error<int> Parse(string text)
{
    if (text.Length == 0)
        return error("empty");
    return text.Length;
}

void Clear(const ref Fixed<int, 2> values)
{
    values[0] = 0;
}

int Main()
{
    int x = 5;
    int* p = &x;
    Fixed<int, 4> f;
    int y = f[4];
    using plain = new Plain();
    Number n = 3;
    if (n is string s)
        return 1;
    Func<int, int, int> wrong = Square;
    Action<int> bump = Bump;
    Func<int, int> sq = Square;
    int z = sq(1, 2);
    Func<int, int> lam = (a, b) => a + b;
    Func<int, int> typed = (string t) => 1;
    var any = (int v) => v + 1;
    int count = 0;
    Action inc = () => { count = count + 1; };
    if (Parse("") is not int v)
        Console.WriteLine("no number");
    return v;
}
