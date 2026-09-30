// unsafe before one statement covers that statement only
// expect-error: pointer dereference is only allowed in an 'unsafe' context
using System;

int Main()
{
    int x = 1;
    unsafe int* p = &x;
    Console.WriteLine(*p);
    return 0;
}
