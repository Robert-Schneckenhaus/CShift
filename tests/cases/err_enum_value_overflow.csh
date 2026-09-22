// expect-error: enum value 300 does not fit into uint8
enum Small : uint8
{
    First = 200 + 100
}

int Main()
{
    return 0;
}
