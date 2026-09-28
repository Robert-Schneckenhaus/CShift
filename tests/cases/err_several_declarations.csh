// Errors in declarations, all in one run: each one is reported and the declarations and function bodies after it are
// still checked.
// expect-error: err_several_declarations.csh:34:1: error: type 'Point' is already defined
// expect-error: err_several_declarations.csh:46:11: error: constant 'Size' is already defined
// expect-error: err_several_declarations.csh:49:5: error: 'counter' is already defined
// expect-error: err_several_declarations.csh:39:31: error: enum member 'One' is declared twice
// expect-error: err_several_declarations.csh:41:15: error: error code 'None' cannot be 0: code 0 means "no specific code" (error codes count from 1)
// expect-error: err_several_declarations.csh:50:6: error: variable 'nothing' cannot have type 'void'
// expect-error: err_several_declarations.csh:52:12: error: the size of Fixed<T, N> must be a number or an integer constant, not 'Bad'
// expect-error: err_several_declarations.csh:53:1: error: 'Slice' expects exactly one type argument (Slice<T>)
// expect-error: err_several_declarations.csh:25:5: error: field 'X' is declared twice
// expect-error: err_several_declarations.csh:26:5: error: field 'Nothing' cannot have type 'void'
// expect-error: err_several_declarations.csh:31:5: error: field 'X' hides an inherited field
// expect-error: err_several_declarations.csh:43:20: error: 'int32' is a member of union 'Shape' twice
// expect-error: err_several_declarations.csh:55:12: error: parameter 'v' cannot have type 'void'
// expect-error: err_several_declarations.csh:57:19: error: a 'thread' function parameter cannot be 'ref' or 'const ref' ('x')
// expect-error: err_several_declarations.csh:59:11: error: 'Enum<T>' is not a type; it gives facts about an enum: Enum<T>.Count, .Min, .Max, .Values, .Names
// expect-error: err_several_declarations.csh:63:19: error: cannot implicitly convert 'int32' to 'string'

using System;

struct Point
{
    int X;
    int X;
    void Nothing;
}

struct Point3 : Point
{
    int X;
}

struct Point
{
    int Z;
}

enum Kind : uint8 { One, Two, One }

error Fault { None = 0, Bad }

union Shape { int, int, string }

const int Size = 1;
const int Size = 2;

int counter;
int counter;
void nothing;

Fixed<int, Bad> cells;
Slice<int, int> pairs;

int Ignore(void v) { return 1; }

thread int Worker(ref int x) { return x; }

int Count(Enum<Kind> e) { return 0; }

int Main()
{
    string text = 5;
    return 0;
}
