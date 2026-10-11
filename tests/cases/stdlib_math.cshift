// Standard library: namespace Math. Main returns the number of failed checks.
// expect-exit: 0

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

bool Near(double a, double b)
{
    return Math.Abs(a - b) < 0.000001;
}

int Main()
{
    int f = 0;

    f += Check("PI", Near(Math.PI, 3.14159265358979));
    f += Check("E", Near(Math.E, 2.71828182845905));
    f += Check("Tau", Near(Math.Tau, 2 * Math.PI));

    f += Check("Abs int", Math.Abs(-5) == 5 && Math.Abs(7) == 7);
    f += Check("Abs int64", Math.Abs(-5000000000) == 5000000000);
    f += Check("Abs double", Math.Abs(-2.5) == 2.5);
    float fl = -1.5f;
    f += Check("Abs float", Math.Abs(fl) == 1.5f);
    f += Check("Min/Max int", Math.Min(3, 9) == 3 && Math.Max(3, 9) == 9);
    f += Check("Min/Max double", Math.Min(2.5, 1.5) == 1.5 && Math.Max(2.5, 1.5) == 2.5);
    f += Check("Min/Max mixed", Math.Max(1, 2.5) == 2.5);
    f += Check("Clamp int", Math.Clamp(15, 0, 10) == 10 && Math.Clamp(-3, 0, 10) == 0 && Math.Clamp(5, 0, 10) == 5);
    f += Check("Clamp double", Math.Clamp(1.5, 0.0, 1.0) == 1.0);
    f += Check("Sign", Math.Sign(-9) == -1 && Math.Sign(0) == 0 && Math.Sign(4) == 1 && Math.Sign(-0.5) == -1);

    f += Check("Sqrt", Math.Sqrt(16) == 4 && Near(Math.Sqrt(2), 1.41421356237));
    f += Check("Cbrt", Near(Math.Cbrt(27), 3));
    f += Check("Pow", Math.Pow(2, 10) == 1024 && Near(Math.Pow(2, 0.5), Math.Sqrt(2)));
    f += Check("Exp/Log", Near(Math.Exp(1), Math.E) && Near(Math.Log(Math.E), 1) && Near(Math.Log10(1000), 3) && Near(Math.Log2(8), 3));
    f += Check("Hypot", Math.Hypot(3, 4) == 5);

    f += Check("Sin/Cos/Tan", Near(Math.Sin(Math.PI / 2), 1) && Near(Math.Cos(Math.PI), -1) && Near(Math.Tan(Math.PI / 4), 1));
    f += Check("Asin/Acos/Atan", Near(Math.Asin(1), Math.PI / 2) && Near(Math.Acos(1), 0) && Near(Math.Atan(1), Math.PI / 4));
    f += Check("Atan2", Near(Math.Atan2(1, 1), Math.PI / 4) && Near(Math.Atan2(0, -1), Math.PI));
    f += Check("hyperbolic", Near(Math.Sinh(0), 0) && Near(Math.Cosh(0), 1) && Near(Math.Tanh(0), 0));
    f += Check("angles", Near(Math.DegreesToRadians(180), Math.PI) && Near(Math.RadiansToDegrees(Math.PI), 180));

    f += Check("Floor", Math.Floor(2.7) == 2 && Math.Floor(-2.2) == -3);
    f += Check("Ceiling", Math.Ceiling(2.1) == 3 && Math.Ceiling(-2.7) == -2);
    f += Check("Truncate", Math.Truncate(2.7) == 2 && Math.Truncate(-2.7) == -2);
    f += Check("Round", Math.Round(2.4) == 2 && Math.Round(2.6) == 3 && Math.Round(2.5) == 2 && Math.Round(3.5) == 4 && Math.Round(-2.5) == -2);

    f += Check("Lerp", Math.Lerp(10, 20, 0.25) == 12.5);
    f += Check("IsNaN", Math.IsNaN(Math.Sqrt(-1)) && !Math.IsNaN(1.0));
    f += Check("IsInfinity", Math.IsInfinity(1.0 / 0.0) && !Math.IsInfinity(5.0));

    // int arguments convert to double
    int n = 9;
    f += Check("int argument", Math.Sqrt(n) == 3 && Math.Pow(n, 2) == 81);

    return f;
}
