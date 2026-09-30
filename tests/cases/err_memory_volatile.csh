// Memory.VolatileRead/VolatileWrite need unsafe, a pointer and the right number of arguments.
// expect-error: Memory.VolatileRead is only allowed in an 'unsafe' context
// expect-error: Memory.VolatileRead needs a pointer, not 'int32'
// expect-error: Memory.VolatileWrite takes two arguments (pointer, value)
int Main()
{
    int x = 1;
    int y = Memory.VolatileRead(&x);
    unsafe
    {
        int z = Memory.VolatileRead(x);
        Memory.VolatileWrite(&x);
    }
    return 0;
}
