// expect-error: depends on itself
const int A = B + 1;
const int B = A + 1;

int Main()
{
    return A;
}
