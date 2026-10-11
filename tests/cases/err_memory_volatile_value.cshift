// The value of Memory.VolatileWrite converts to the type the pointer points to.
// expect-error: cannot implicitly convert 'string' to 'int32'
int Main()
{
    unsafe
    {
        int x = 1;
        Memory.VolatileWrite(&x, "text");
    }
    return 0;
}
