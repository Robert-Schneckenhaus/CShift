//! Math functions and constants: `Math.Sqrt(2.0)`, `Math.Max(a, b)`, `Math.PI`, ...
//!
//! ```
//! double area = Math.PI * r * r;
//! int clamped = Math.Clamp(value, 0, 255);
//! ```
//!
//! The trigonometric functions use radians ([Math.DegreesToRadians] converts). For integer trigonometry without
//! floating point (e.g. on a 68000) there is [FastTrig].

namespace Math;

using System.Native;

/// The ratio of a circle's circumference to its diameter, π (3.14159...).
const double PI = 3.14159265358979323846;
/// The base of the natural logarithm, e (2.71828...).
const double E = 2.71828182845904523536;
/// The ratio of a circle's circumference to its radius, τ = 2π (6.28318...).
const double Tau = 6.28318530717958647692;

// ---- Abs / Min / Max / Clamp / Sign ----

/// The absolute value of `x`.
int Abs(int x)
{
    if (x < 0)
        return -x;
    return x;
}

/// The absolute value of `x`.
int64 Abs(int64 x)
{
    if (x < 0)
        return -x;
    return x;
}

/// The absolute value of `x`.
float Abs(float x)
{
    if (x < 0)
        return -x;
    return x;
}

/// The absolute value of `x`.
double Abs(double x)
{
    return fabs(x);
}

/// The smaller of `a` and `b`.
int Min(int a, int b)
{
    if (a < b)
        return a;
    return b;
}

/// The smaller of `a` and `b`.
int64 Min(int64 a, int64 b)
{
    if (a < b)
        return a;
    return b;
}

/// The smaller of `a` and `b`.
float Min(float a, float b)
{
    if (a < b)
        return a;
    return b;
}

/// The smaller of `a` and `b`.
double Min(double a, double b)
{
    if (a < b)
        return a;
    return b;
}

/// The larger of `a` and `b`.
int Max(int a, int b)
{
    if (a > b)
        return a;
    return b;
}

/// The larger of `a` and `b`.
int64 Max(int64 a, int64 b)
{
    if (a > b)
        return a;
    return b;
}

/// The larger of `a` and `b`.
float Max(float a, float b)
{
    if (a > b)
        return a;
    return b;
}

/// The larger of `a` and `b`.
double Max(double a, double b)
{
    if (a > b)
        return a;
    return b;
}

/// `value` limited to the range from `min` to `max`.
/// @returns `min` if `value` is smaller, `max` if it is larger, otherwise `value`.
int Clamp(int value, int min, int max)
{
    return Min(Max(value, min), max);
}

/// `value` limited to the range from `min` to `max`.
/// @returns `min` if `value` is smaller, `max` if it is larger, otherwise `value`.
int64 Clamp(int64 value, int64 min, int64 max)
{
    return Min(Max(value, min), max);
}

/// `value` limited to the range from `min` to `max`.
/// @returns `min` if `value` is smaller, `max` if it is larger, otherwise `value`.
float Clamp(float value, float min, float max)
{
    return Min(Max(value, min), max);
}

/// `value` limited to the range from `min` to `max`.
/// @returns `min` if `value` is smaller, `max` if it is larger, otherwise `value`.
double Clamp(double value, double min, double max)
{
    return Min(Max(value, min), max);
}

/// The sign of `x`.
/// @returns -1 for a negative `x`, 0 for 0, 1 for a positive `x`.
int Sign(int x)
{
    if (x < 0)
        return -1;
    if (x > 0)
        return 1;
    return 0;
}

/// The sign of `x`.
/// @returns -1 for a negative `x`, 0 for 0 (and NaN), 1 for a positive `x`.
int Sign(double x)
{
    if (x < 0)
        return -1;
    if (x > 0)
        return 1;
    return 0;
}

// ---- Rounding ----

/// The largest integer that is not larger than `x` (rounds towards negative infinity): `Floor(-1.5)` is -2.
double Floor(double x)
{
    return floor(x);
}

/// The smallest integer that is not smaller than `x` (rounds towards positive infinity): `Ceiling(1.2)` is 2.
double Ceiling(double x)
{
    return ceil(x);
}

/// `x` without its fractional part (rounds towards zero): `Truncate(-1.7)` is -1.
double Truncate(double x)
{
    return trunc(x);
}

/// `x` rounded to the nearest integer; halves go to the even neighbour (2.5 becomes 2, 3.5 becomes 4), like C#.
double Round(double x)
{
    return nearbyint(x);
}

// ---- Powers, roots, logarithms ----

/// The square root of `x`.
/// @returns NaN for a negative `x`.
double Sqrt(double x)
{
    return sqrt(x);
}

/// The cube root of `x` (also for a negative `x`).
double Cbrt(double x)
{
    return cbrt(x);
}

/// `x` to the power of `y`.
double Pow(double x, double y)
{
    return pow(x, y);
}

/// e to the power of `x`.
double Exp(double x)
{
    return exp(x);
}

/// The natural logarithm (base e) of `x`.
/// @returns negative infinity for 0, NaN for a negative `x`.
double Log(double x)
{
    return log(x);
}

/// The logarithm of `x` to base 2.
/// @returns negative infinity for 0, NaN for a negative `x`.
double Log2(double x)
{
    return log2(x);
}

/// The logarithm of `x` to base 10.
/// @returns negative infinity for 0, NaN for a negative `x`.
double Log10(double x)
{
    return log10(x);
}

/// The length of the hypotenuse, `Sqrt(x * x + y * y)`, without overflowing in between.
double Hypot(double x, double y)
{
    return hypot(x, y);
}

// ---- Trigonometry ----

/// The sine of the angle `x` (in radians).
double Sin(double x)
{
    return sin(x);
}

/// The cosine of the angle `x` (in radians).
double Cos(double x)
{
    return cos(x);
}

/// The tangent of the angle `x` (in radians).
double Tan(double x)
{
    return tan(x);
}

/// The angle (in radians, -π/2 to π/2) whose sine is `x`.
/// @returns NaN if `x` is outside of -1 to 1.
double Asin(double x)
{
    return asin(x);
}

/// The angle (in radians, 0 to π) whose cosine is `x`.
/// @returns NaN if `x` is outside of -1 to 1.
double Acos(double x)
{
    return acos(x);
}

/// The angle (in radians, -π/2 to π/2) whose tangent is `x`.
double Atan(double x)
{
    return atan(x);
}

/// The angle (in radians, -π to π) of the point (`x`, `y`): unlike `Atan(y / x)` it knows the quadrant and handles
/// `x == 0`.
double Atan2(double y, double x)
{
    return atan2(y, x);
}

/// The hyperbolic sine of `x`.
double Sinh(double x)
{
    return sinh(x);
}

/// The hyperbolic cosine of `x`.
double Cosh(double x)
{
    return cosh(x);
}

/// The hyperbolic tangent of `x`.
double Tanh(double x)
{
    return tanh(x);
}

/// An angle in degrees converted to radians.
double DegreesToRadians(double degrees)
{
    return degrees * PI / 180;
}

/// An angle in radians converted to degrees.
double RadiansToDegrees(double radians)
{
    return radians * 180 / PI;
}

// ---- Misc ----

/// Linear interpolation between `a` and `b`: `a + (b - a) * t`, so `a` for `t` = 0 and `b` for `t` = 1.
double Lerp(double a, double b, double t)
{
    return a + (b - a) * t;
}

/// Whether `x` is NaN ("not a number", e.g. the result of `0.0 / 0.0`).
bool IsNaN(double x)
{
    return x != x;
}

/// Whether `x` is positive or negative infinity.
bool IsInfinity(double x)
{
    return x == double.PositiveInfinity || x == double.NegativeInfinity;
}
