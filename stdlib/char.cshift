//! Classifying and converting characters (ASCII), like `System.Char` in C#:
//!
//! ```
//! if (Char.IsDigit(c))
//!     value = value * 10 + (c - '0');
//! ```
//!
//! A `char` is a byte of UTF-8 text: the functions only know the ASCII characters; every byte above 127 is neither a
//! letter nor a digit.

namespace Char;

/// Whether `c` is a decimal digit (`0` to `9`).
bool IsDigit(char c)
{
    return c >= '0' && c <= '9';
}

/// Whether `c` is an uppercase ASCII letter (`A` to `Z`).
bool IsUpper(char c)
{
    return c >= 'A' && c <= 'Z';
}

/// Whether `c` is a lowercase ASCII letter (`a` to `z`).
bool IsLower(char c)
{
    return c >= 'a' && c <= 'z';
}

/// Whether `c` is an ASCII letter.
bool IsLetter(char c)
{
    return IsUpper(c) || IsLower(c);
}

/// Whether `c` is an ASCII letter or a decimal digit.
bool IsLetterOrDigit(char c)
{
    return IsLetter(c) || IsDigit(c);
}

/// Whether `c` is a hexadecimal digit (`0` to `9`, `a` to `f`, `A` to `F`).
bool IsHexDigit(char c)
{
    return IsDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

/// Whether `c` is white space: a space, a tab, a line break (`\n`, `\r`), a vertical tab or a form feed.
bool IsWhiteSpace(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

/// `c` as an uppercase letter; any other character stays as it is.
char ToUpper(char c)
{
    if (IsLower(c))
        return (char)(c - 32);
    return c;
}

/// `c` as a lowercase letter; any other character stays as it is.
char ToLower(char c)
{
    if (IsUpper(c))
        return (char)(c + 32);
    return c;
}

/// The value of a hexadecimal digit (0 to 15).
/// @returns -1 if `c` is not a hexadecimal digit.
int HexValue(char c)
{
    if (IsDigit(c))
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}
