// A struct can only have one base struct.
// expect-error: the base struct must be listed first
struct A
{
    int X;
}

struct B
{
    int Y;
}

struct C : A, B
{
    int Z;
}

int Main()
{
    return 0;
}
