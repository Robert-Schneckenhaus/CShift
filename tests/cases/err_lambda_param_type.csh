// Written parameter types must match the function type.
// expect-error: parameter 'x' of the lambda has type 'string', but 'Func<int32, int32>' needs 'int32'

using System;

int Main()
{
    Func<int, int> f = (string x) => 1;
    return 0;
}
