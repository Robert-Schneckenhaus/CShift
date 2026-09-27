// Errors in calls through interface parameters and unions, all in one run.
// expect-error: err_several_interfaces.csh:26:15: error: interface 'IShape' has no method 'Grow' that takes these arguments
// expect-error: err_several_interfaces.csh:27:17: error: interface 'IShape' has no method 'Rotate' that takes these arguments
// expect-error: err_several_interfaces.csh:28:26: error: cannot implicitly convert 'float64' to 'int32' (an explicit cast is required)
// expect-error: err_several_interfaces.csh:36:13: error: union 'Shape' has no method 'Shrink' (it can call the methods of the interfaces it lists)

using System;

interface IShape
{
    double Area();
    void Grow(double factor);
}

struct Circle : IShape
{
    double R;
    double Area() { return 3.0 * R * R; }
    void Grow(double factor) { R = R * factor; }
}

union Shape : IShape { Circle }

double Describe(ref IShape shape)
{
    shape.Grow("big");
    shape.Rotate();
    int area = shape.Area();
    return shape.Area();
}

int Main()
{
    Shape s = Circle { R = 1.0 };
    s.Grow(2.0);
    s.Shrink();
    return 0;
}
