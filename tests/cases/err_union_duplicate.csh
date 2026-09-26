// Each member type appears once (the type tells the members apart).
// expect-error: 'int32' is a member of union 'Value' twice

union Value { int, string, int32 }

int Main()
{
    Value v = 1;
    return 0;
}
