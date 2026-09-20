// Math functions: Math.Sqrt(2.0), Math.Max(a, b), Math.PI, ...
// Trigonometric functions use radians.

namespace Math;

using System.Native;

const double PI = 3.14159265358979323846;
const double E = 2.71828182845904523536;
const double Tau = 6.28318530717958647692;

// ---- Abs / Min / Max / Clamp / Sign ----

int Abs(int x)
{
    if (x < 0)
        return -x;
    return x;
}

int64 Abs(int64 x)
{
    if (x < 0)
        return -x;
    return x;
}

float Abs(float x)
{
    if (x < 0)
        return -x;
    return x;
}

double Abs(double x)
{
    return fabs(x);
}

int Min(int a, int b)
{
    if (a < b)
        return a;
    return b;
}

int64 Min(int64 a, int64 b)
{
    if (a < b)
        return a;
    return b;
}

float Min(float a, float b)
{
    if (a < b)
        return a;
    return b;
}

double Min(double a, double b)
{
    if (a < b)
        return a;
    return b;
}

int Max(int a, int b)
{
    if (a > b)
        return a;
    return b;
}

int64 Max(int64 a, int64 b)
{
    if (a > b)
        return a;
    return b;
}

float Max(float a, float b)
{
    if (a > b)
        return a;
    return b;
}

double Max(double a, double b)
{
    if (a > b)
        return a;
    return b;
}

int Clamp(int value, int min, int max)
{
    return Min(Max(value, min), max);
}

int64 Clamp(int64 value, int64 min, int64 max)
{
    return Min(Max(value, min), max);
}

float Clamp(float value, float min, float max)
{
    return Min(Max(value, min), max);
}

double Clamp(double value, double min, double max)
{
    return Min(Max(value, min), max);
}

// -1, 0 or 1
int Sign(int x)
{
    if (x < 0)
        return -1;
    if (x > 0)
        return 1;
    return 0;
}

int Sign(double x)
{
    if (x < 0)
        return -1;
    if (x > 0)
        return 1;
    return 0;
}

// ---- Rounding ----

double Floor(double x)
{
    return floor(x);
}

double Ceiling(double x)
{
    return ceil(x);
}

double Truncate(double x)
{
    return trunc(x);
}

// Rounds to the nearest integer; halves go to the even neighbour (2.5 -> 2, 3.5 -> 4), like C#.
double Round(double x)
{
    return nearbyint(x);
}

// ---- Powers, roots, logarithms ----

double Sqrt(double x)
{
    return sqrt(x);
}

double Cbrt(double x)
{
    return cbrt(x);
}

double Pow(double x, double y)
{
    return pow(x, y);
}

double Exp(double x)
{
    return exp(x);
}

// Natural logarithm.
double Log(double x)
{
    return log(x);
}

double Log2(double x)
{
    return log2(x);
}

double Log10(double x)
{
    return log10(x);
}

// sqrt(x * x + y * y) without intermediate overflow.
double Hypot(double x, double y)
{
    return hypot(x, y);
}

// ---- Trigonometry ----

double Sin(double x)
{
    return sin(x);
}

double Cos(double x)
{
    return cos(x);
}

double Tan(double x)
{
    return tan(x);
}

double Asin(double x)
{
    return asin(x);
}

double Acos(double x)
{
    return acos(x);
}

double Atan(double x)
{
    return atan(x);
}

double Atan2(double y, double x)
{
    return atan2(y, x);
}

double Sinh(double x)
{
    return sinh(x);
}

double Cosh(double x)
{
    return cosh(x);
}

double Tanh(double x)
{
    return tanh(x);
}

double DegreesToRadians(double degrees)
{
    return degrees * PI / 180;
}

double RadiansToDegrees(double radians)
{
    return radians * 180 / PI;
}

// ---- Misc ----

// Linear interpolation: a + (b - a) * t
double Lerp(double a, double b, double t)
{
    return a + (b - a) * t;
}

bool IsNaN(double x)
{
    return x != x;
}

bool IsInfinity(double x)
{
    return x == double.PositiveInfinity || x == double.NegativeInfinity;
}
