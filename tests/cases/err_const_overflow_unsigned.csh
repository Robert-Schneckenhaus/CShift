// expect-error: integer overflow in a constant expression
const uint32 Three = 3;
const uint32 Bad = Three - 5;

int Main()
{
    return 0;
}
