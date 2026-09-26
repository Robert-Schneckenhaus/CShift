// A switch over a union without 'default:' must handle every member.
// expect-error: the switch over union 'Value' does not handle 'string', 'bool'; add the cases or 'default:'

using System;

union Value { int, string, bool }

int Main()
{
    Value v = "text";
    switch (v)
    {
        case int i:
            return i;
    }
    return 0;
}
