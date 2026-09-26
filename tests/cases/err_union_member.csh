// 'is' and 'case' on a union take one of its member types.
// expect-error: 'string' is not a member of union 'Number'

union Number { int, double }

int Main()
{
    Number n = 3;
    if (n is string s)
        return 1;
    return 0;
}
