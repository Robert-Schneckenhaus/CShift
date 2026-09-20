// Second source file of the test program: demonstrates namespaces and
// resolution of symbols across files without headers or forward declarations.

namespace MathLib;

int Square(int x)
{
    return x * x;
}

// Calls a function that is defined further below (no forward declaration needed).
int SumOfSquares(int a, int b)
{
    return Square(a) + Square(b) + Zero();
}

int Zero()
{
    return 0;
}

struct Point3
{
    int X;
    int Y;
    int Z;

    int Sum()
    {
        return X + Y + Z;
    }
}

enum Mode : uint8
{
    Fast,
    Slow = 10,
    Off
}
