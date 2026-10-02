// A name can be declared only once in a block (an inner block may reuse it).
// expect-error: 'count' is already declared in this block
using System;

int Main()
{
    int count = 1;
    {
        int count = 2;          // fine: an inner block
        Console.WriteLine(count);
    }
    int count = 3;
    return count;
}
