// The declarations of the built-in types (see README.md in this folder): only for the documentation.

//! The types, functions and namespaces that the compiler provides itself: [string], the numbers ([int32], [double],
//! ...), [bool], [char], arrays ([Array]), slices ([Slice], [ReadOnlySlice], [StringSlice]), [Fixed], [Optional],
//! [Error], [Console], [Environment], [Memory], [Thread], [SharedPtr], [Enum], [Action] and [Func]. They need no
//! `using`.

/// A signed 8-bit integer.
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct int8 : IComparable<int8>, IEquatable<int8>, IHashable
{
    /// The smallest value, -128.
    static int8 MinValue;
    /// The largest value, 127.
    static int8 MaxValue;

    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(int8 other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(int8 other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// A signed 16-bit integer.
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct int16 : IComparable<int16>, IEquatable<int16>, IHashable
{
    /// The smallest value, -32768.
    static int16 MinValue;
    /// The largest value, 32767.
    static int16 MaxValue;

    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(int16 other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(int16 other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// A signed 32-bit integer; `int` is the same type.
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct int32 : IComparable<int32>, IEquatable<int32>, IHashable
{
    /// The smallest value, -2147483648.
    static int32 MinValue;
    /// The largest value, 2147483647.
    static int32 MaxValue;

    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(int32 other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(int32 other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// A signed 64-bit integer.
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct int64 : IComparable<int64>, IEquatable<int64>, IHashable
{
    /// The smallest value, -9223372036854775808.
    static int64 MinValue;
    /// The largest value, 9223372036854775807.
    static int64 MaxValue;

    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(int64 other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(int64 other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// An unsigned 8-bit integer (a byte); it converts implicitly to and from `char`.
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct uint8 : IComparable<uint8>, IEquatable<uint8>, IHashable
{
    /// The smallest value, 0.
    static uint8 MinValue;
    /// The largest value, 255.
    static uint8 MaxValue;

    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(uint8 other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(uint8 other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// An unsigned 16-bit integer.
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct uint16 : IComparable<uint16>, IEquatable<uint16>, IHashable
{
    /// The smallest value, 0.
    static uint16 MinValue;
    /// The largest value, 65535.
    static uint16 MaxValue;

    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(uint16 other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(uint16 other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// An unsigned 32-bit integer; `uint` is the same type.
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct uint32 : IComparable<uint32>, IEquatable<uint32>, IHashable
{
    /// The smallest value, 0.
    static uint32 MinValue;
    /// The largest value, 4294967295.
    static uint32 MaxValue;

    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(uint32 other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(uint32 other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// An unsigned 64-bit integer.
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct uint64 : IComparable<uint64>, IEquatable<uint64>, IHashable
{
    /// The smallest value, 0.
    static uint64 MinValue;
    /// The largest value, 18446744073709551615.
    static uint64 MaxValue;

    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(uint64 other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(uint64 other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// A signed integer of the size of a pointer (64 or 32 bits, like C's `intptr_t`).
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct nint : IComparable<nint>, IEquatable<nint>, IHashable
{
    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(nint other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(nint other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// An unsigned integer of the size of a pointer (like C's `size_t`).
///
/// Arithmetic is checked: an overflow, a division by zero or a conversion that loses the value ends the program
/// with a panic, unless the code is `unchecked` (then it wraps around). See the language guide (basics).
struct nuint : IComparable<nuint>, IEquatable<nuint>, IHashable
{
    /// The number as decimal text: `42.ToString()` is `"42"`.
    string ToString();

    /// The number in a number format: `255.ToString("X4")` is `"00FF"` (see [NumberFormat]).
    /// @param format `D`, `X`, `B`, `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`).
    bool Equals(nuint other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(nuint other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// A 32-bit floating point number (IEEE 754 single precision); `float32` is the same type.
///
/// Floating point arithmetic is not checked: it gives infinity or NaN instead of a panic.
struct float : IComparable<float>, IEquatable<float>, IHashable
{
    /// The smallest (most negative) finite value.
    static float MinValue;
    /// The largest finite value.
    static float MaxValue;
    /// The difference between 1 and the next larger value.
    static float Epsilon;
    /// "Not a number", e.g. the result of `0.0 / 0.0`; it is not equal to anything, not even to itself.
    static float NaN;
    /// Positive infinity, e.g. the result of `1.0 / 0.0`.
    static float PositiveInfinity;
    /// Negative infinity.
    static float NegativeInfinity;

    /// The number as text, with as many digits as needed to read it back exactly: `0.1.ToString()` is `"0.1"`.
    string ToString();

    /// The number in a number format: `3.14159.ToString("F2")` is `"3.14"` (see [NumberFormat]).
    /// @param format `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`; NaN is not equal to NaN).
    bool Equals(float other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(float other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// A 64-bit floating point number (IEEE 754 double precision); `float64` is the same type.
///
/// Floating point arithmetic is not checked: it gives infinity or NaN instead of a panic.
struct double : IComparable<double>, IEquatable<double>, IHashable
{
    /// The smallest (most negative) finite value.
    static double MinValue;
    /// The largest finite value.
    static double MaxValue;
    /// The difference between 1 and the next larger value.
    static double Epsilon;
    /// "Not a number", e.g. the result of `0.0 / 0.0`; it is not equal to anything, not even to itself.
    static double NaN;
    /// Positive infinity, e.g. the result of `1.0 / 0.0`.
    static double PositiveInfinity;
    /// Negative infinity.
    static double NegativeInfinity;

    /// The number as text, with as many digits as needed to read it back exactly: `0.1.ToString()` is `"0.1"`.
    string ToString();

    /// The number in a number format: `3.14159.ToString("F2")` is `"3.14"` (see [NumberFormat]).
    /// @param format `F`, `N`, `E`, `P` or `G`, optionally followed by up to two digits.
    string ToString(string format);

    /// Whether the numbers are equal (also `a == b`; NaN is not equal to NaN).
    bool Equals(double other);

    /// Compares the numbers: -1, 0 or 1.
    int CompareTo(double other);

    /// A hash code of the number, for [Dictionary] keys.
    int GetHashCode();
}

/// `true` or `false`.
struct bool : IEquatable<bool>, IHashable
{
    /// `"true"` or `"false"`.
    string ToString();

    /// Whether the values are equal (also `a == b`).
    bool Equals(bool other);

    /// A hash code of the value, for [Dictionary] keys.
    int GetHashCode();
}

/// A byte of text, a type of its own that converts implicitly to and from [uint8] (and to the larger integer
/// types). A character literal like `'a'` is its ASCII code; arithmetic on it gives an `int` (`'a' + 1` is 98).
///
/// A `char` is one byte of UTF-8, so a character beyond ASCII is several `char`s. The namespace [Char] classifies
/// and converts them (`Char.IsDigit(c)`).
struct char : IComparable<char>, IEquatable<char>, IHashable
{
    /// A string of the one character.
    string ToString();

    /// Whether the characters are equal (also `a == b`).
    bool Equals(char other);

    /// Compares the codes: -1, 0 or 1.
    int CompareTo(char other);

    /// A hash code of the character, for [Dictionary] keys.
    int GetHashCode();
}
