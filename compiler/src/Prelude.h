#pragma once

// Declarations that are always available in every CShift program.
// The prelude is written in CShift itself and parsed before the user's files.
inline const char* preludeSource()
{
    return R"CSH(
interface IDisposable
{
    void Dispose();
}

interface IComparable<T>
{
    int CompareTo(T other);
}

extern "C" double sqrt(double x);
extern "C" float sqrtf(float x);

float sqrt(float x)
{
    return sqrtf(x);
}
)CSH";
}
