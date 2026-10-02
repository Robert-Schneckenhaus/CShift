//! The declarations that every CShift program sees without a `using`: the interfaces the language itself relies on
//! (`using` with [IDisposable], sorting with [IComparable], equality and hashing for collections) and
//! `sqrt`.

/// A resource that has to be released: `using (var f = ...) { ... }` calls [IDisposable.Dispose] at the end of the
/// block, also when it is left early.
interface IDisposable
{
    /// Releases the resource. It is called once, at the end of the `using` block.
    void Dispose();
}

/// Values that have an order: [List<T>.Sort] and the comparison of keys use it.
///
/// Numbers, `char` and `string` implement it, and so can any struct that defines `CompareTo`.
interface IComparable<T>
{
    /// Compares this value with another one.
    /// @returns a negative number if this value comes before `other`, 0 if they are equal, a positive number if it
    /// comes after.
    int CompareTo(T other);
}

/// Equality for generic containers ([List<T>.IndexOf], [List<T>.Contains], the keys of a [Dictionary]).
///
/// Numbers, `bool`, `char`, enums and `string` implement it; a struct implements it by defining `Equals`.
interface IEquatable<T>
{
    /// Whether this value equals `other`.
    bool Equals(T other);
}

/// Hash codes for the keys of a [Dictionary] and the values of a [HashSet].
///
/// Equal values (see [IEquatable]) must return equal hash codes.
interface IHashable
{
    /// The hash code of the value: equal values return the same code; different values should rarely do.
    int GetHashCode();
}

/// The square root of `x` (the C library's `sqrt`).
/// @returns NaN for a negative `x`.
extern "C" double sqrt(double x);
extern "C" float sqrtf(float x);

/// The square root of `x` as a `float` (the C library's `sqrtf`).
/// @returns NaN for a negative `x`.
float sqrt(float x)
{
    return sqrtf(x);
}
