// Errors in constant values and in the initializers of globals, all in one run; what is computed from them is not
// reported again.
// expect-error: err_several_constants.csh:17:27: error: enum value 300 does not fit into uint8
// expect-error: err_several_constants.csh:19:20: error: division by zero in constant expression
// expect-error: err_several_constants.csh:20:29: error: integer overflow in a constant expression (the value does not fit into int32)
// expect-error: err_several_constants.csh:22:25: error: operator '-' cannot be applied to 'string' and 'string'
// expect-error: err_several_constants.csh:23:19: error: operator '!' cannot be applied to 'int32'
// expect-error: err_several_constants.csh:24:13: error: a constant cannot be 'int32[]' (its elements could be changed); use 'const ReadOnlySlice<int32>'
// expect-error: err_several_constants.csh:26:24: error: index 5 is out of range (the constant slice has 2 elements)
// expect-error: err_several_constants.csh:27:23: error: an index must be an integer, not 'string'
// expect-error: err_several_constants.csh:28:15: error: cannot implicitly convert 'string' to 'int32'
// expect-error: err_several_constants.csh:29:16: error: undefined name 'missing'
// expect-error: err_several_constants.csh:33:25: error: operator '<<' cannot be applied to 'int32' and 'bool'
// expect-error: err_several_constants.csh:34:13: error: cannot implicitly convert 'string' to 'int32'

using System;
enum Color : uint8 { Red, Big = 300 }
const int Zero = 0;
const int Div = 10 / Zero;
const int Over = 2147483647 + 1;
const int FromDiv = Div + 1;
const string Name = "a" - "b";
const bool Flag = !5;
const int[] Arr = [1];
const ReadOnlySlice<int> Items = [1, 2];
const int Third = Items[5];
const int Bad = Items["x"];
int counter = "one";
string label = missing;
int total = counter + 1;
int Main()
{
    const int local = 1 << true;
    int y = "s";
    return Div + Over + FromDiv;
}
