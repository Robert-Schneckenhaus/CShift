// Core declarations that are visible in every CShift program (global namespace).

interface IDisposable
{
    void Dispose();
}

// Implemented by numbers, char and string as well as by user structs that define CompareTo.
interface IComparable<T>
{
    int CompareTo(T other);
}

// Equality for generic containers (List<T>.IndexOf, Dictionary keys, ...).
// Implemented by numbers, bool, char, enums and string.
interface IEquatable<T>
{
    bool Equals(T other);
}

// Hash codes for Dictionary keys. Equal values (IEquatable) must return equal hash codes.
interface IHashable
{
    int GetHashCode();
}

extern "C" double sqrt(double x);
extern "C" float sqrtf(float x);

float sqrt(float x)
{
    return sqrtf(x);
}
