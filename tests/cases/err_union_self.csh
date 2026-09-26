// A union cannot contain itself (its size would be infinite).
// expect-error: contains itself

struct Node
{
    Tree Left;
}

union Tree { int, Node }

int Main()
{
    Tree t = 1;
    return 0;
}
