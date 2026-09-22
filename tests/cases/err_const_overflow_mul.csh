// expect-error: integer overflow in a constant expression
const int64 Big = 9223372036854775807 * 2;

int Main()
{
    return 0;
}
