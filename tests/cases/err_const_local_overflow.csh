// expect-error: integer overflow in a constant expression
int Main()
{
    const int8 Small = 100;
    const int Fine = Small * 2;
    const int Bad = 65536 * 65536;
    return Fine + Bad;
}
