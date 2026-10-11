// Memory.VolatileWrite accesses one value: a number, bool, char, enum or pointer (not a string).
// expect-error: Memory.VolatileWrite needs a pointer to a number, bool, char, enum or pointer, not 'string*'
int Main()
{
    unsafe
    {
        string s = "a";
        Memory.VolatileWrite(&s, "b");
    }
    return 0;
}
