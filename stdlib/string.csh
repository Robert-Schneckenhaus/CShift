//! The methods of strings. The compiler forwards the string methods it does not know itself to this namespace:
//!
//! ```
//! "a,b".Contains(",")        // is String.Contains("a,b", ",")
//! string.Join(", ", parts)   // is String.Join(", ", parts)
//! ```
//!
//! The functions take a `StringSlice` (a string converts to one for free, and `s[i..j]` is one), so they work on parts
//! of a string without copying; [String.Trim], [String.Split] and [String.Substring] return slices as well. Copy a
//! result with `.ToString()` to keep it as a string.
//!
//! Strings are UTF-8. Positions and lengths are byte offsets (like `s.Length` and `s[i]`). Case conversion only
//! handles ASCII letters.

namespace String;

using System;
using System.Native;

/// Whether `s` is empty (a `null` string is empty too).
bool IsNullOrEmpty(StringSlice s)
{
    return s.Length == 0; // a null string is an empty slice
}

// ---- IEquatable<string>, IHashable and IComparable<string> (used by generic containers) ----

/// Whether `a` and `b` have the same bytes (`a == b`).
bool Equals(string a, string b)
{
    return a == b;
}

/// A hash code of `s` (FNV-1a), for [Dictionary] keys: equal strings have equal codes.
int GetHashCode(string s)
{
    uint hash = 2166136261;
    for (var i = 0; i < s.Length; i += 1)
        hash = unchecked((hash ^ (uint)s[i]) * 16777619);
    return (int)hash;
}

/// Compares `a` and `b` by their UTF-8 bytes (ordinal, no locale).
/// @returns -1 if `a` comes first, 0 if they are equal, 1 if `b` comes first.
int CompareTo(string a, string b)
{
    int la = a.Length;
    int lb = b.Length;
    int n = la < lb ? la : lb;
    for (var i = 0; i < n; i += 1)
    {
        if (a[i] != b[i])
        {
            if (a[i] < b[i])
                return -1;
            return 1;
        }
    }
    if (la < lb)
        return -1;
    if (la > lb)
        return 1;
    return 0;
}

// ---- The same for StringSlice: slices can be keys of a Dictionary or sorted in a List ----

/// Whether `a` and `b` have the same bytes (`a == b`).
bool Equals(StringSlice a, StringSlice b)
{
    return a == b;
}

/// A hash code of `s` (FNV-1a): the same as for a string with the same text.
int GetHashCode(StringSlice s)
{
    uint hash = 2166136261;
    for (var i = 0; i < s.Length; i += 1)
        hash = unchecked((hash ^ (uint)s[i]) * 16777619);
    return (int)hash;
}

/// Compares `a` and `b` by their UTF-8 bytes (ordinal, no locale), like strings.
/// @returns -1 if `a` comes first, 0 if they are equal, 1 if `b` comes first.
int CompareTo(StringSlice a, StringSlice b)
{
    int la = a.Length;
    int lb = b.Length;
    int n = la < lb ? la : lb;
    for (var i = 0; i < n; i += 1)
    {
        if (a[i] != b[i])
        {
            if (a[i] < b[i])
                return -1;
            return 1;
        }
    }
    if (la < lb)
        return -1;
    if (la > lb)
        return 1;
    return 0;
}

// ---- Searching ----

/// The position of the first occurrence of `value` in `s` at or after `start`.
/// @returns -1 if there is none.
int IndexOf(StringSlice s, StringSlice value, int start)
{
    int n = s.Length;
    int m = value.Length;
    for (var i = start; i >= 0 && i + m <= n; i += 1)
    {
        int j = 0;
        while (j < m && s[i + j] == value[j])
            j += 1;
        if (j == m)
            return i;
    }
    return -1;
}

/// The position of the first occurrence of `value` in `s`.
/// @returns -1 if there is none.
int IndexOf(StringSlice s, StringSlice value)
{
    return IndexOf(s, value, 0);
}

/// The position of the first occurrence of the character `value` in `s`.
/// @returns -1 if there is none.
int IndexOf(StringSlice s, char value)
{
    return IndexOf(s, value, 0);
}

/// The position of the first occurrence of the character `value` in `s` at or after `start`.
/// @returns -1 if there is none.
int IndexOf(StringSlice s, char value, int start)
{
    for (var i = start < 0 ? 0 : start; i < s.Length; i += 1)
    {
        if (s[i] == value)
            return i;
    }
    return -1;
}

/// The position of the last occurrence of the character `value` in `s`.
/// @returns -1 if there is none.
int LastIndexOf(StringSlice s, char value)
{
    for (var i = s.Length - 1; i >= 0; i -= 1)
    {
        if (s[i] == value)
            return i;
    }
    return -1;
}

/// Whether `value` occurs in `s`.
bool Contains(StringSlice s, StringSlice value)
{
    return IndexOf(s, value, 0) >= 0;
}

/// Whether the character `value` occurs in `s`.
bool Contains(StringSlice s, char value)
{
    return IndexOf(s, value) >= 0;
}

/// Whether `s` starts with `prefix`.
bool StartsWith(StringSlice s, StringSlice prefix)
{
    return prefix.Length <= s.Length && s[..prefix.Length] == prefix;
}

/// Whether `s` ends with `suffix`.
bool EndsWith(StringSlice s, StringSlice suffix)
{
    return suffix.Length <= s.Length && s[s.Length - suffix.Length..] == suffix;
}

// ---- Transforming ----

/// The part of `s` from `start` to the end, as a view: `s[start..]`. (`string.Substring` of a string is built in and
/// copies.)
StringSlice Substring(StringSlice s, int start)
{
    return s[start..];
}

/// The `count` bytes of `s` from `start`, as a view: `s[start..start + count]`.
StringSlice Substring(StringSlice s, int start, int count)
{
    return s[start..start + count];
}

/// Whether `c` is a space, a tab or a line break (`\n`, `\r`): the white space that [String.Trim] removes.
bool IsSpace(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

/// `s` without the white space at both ends (a view of `s`, nothing is copied).
StringSlice Trim(StringSlice s)
{
    int start = 0;
    int end = s.Length;
    while (start < end && IsSpace(s[start]))
        start += 1;
    while (end > start && IsSpace(s[end - 1]))
        end -= 1;
    return s[start..end];
}

/// `s` without the white space at the start (a view).
StringSlice TrimStart(StringSlice s)
{
    int start = 0;
    while (start < s.Length && IsSpace(s[start]))
        start += 1;
    return s[start..];
}

/// `s` without the white space at the end (a view).
StringSlice TrimEnd(StringSlice s)
{
    int end = s.Length;
    while (end > 0 && IsSpace(s[end - 1]))
        end -= 1;
    return s[..end];
}

/// `s` without the character `c` at the start (a view): `"007".TrimStart('0')` is `"7"`.
StringSlice TrimStart(StringSlice s, char c)
{
    int start = 0;
    while (start < s.Length && s[start] == c)
        start += 1;
    return s[start..];
}

/// `s` without the character `c` at the end (a view): `"1.500".TrimEnd('0')` is `"1.5"`.
StringSlice TrimEnd(StringSlice s, char c)
{
    int end = s.Length;
    while (end > 0 && s[end - 1] == c)
        end -= 1;
    return s[..end];
}

/// `s` filled up to `width` characters (bytes) with spaces on the left: `"7".PadLeft(3)` is `"  7"`.
string PadLeft(StringSlice s, int width)
{
    return PadLeft(s, width, ' ');
}

/// `s` filled up to `width` characters (bytes) with `fill` on the left: `"7".PadLeft(3, '0')` is `"007"`.
string PadLeft(StringSlice s, int width, char fill)
{
    if (s.Length >= width)
        return s.ToString();
    return Repeat(fill.ToString(), width - s.Length) + s;
}

/// `s` filled up to `width` characters (bytes) with spaces on the right.
string PadRight(StringSlice s, int width)
{
    return PadRight(s, width, ' ');
}

/// `s` filled up to `width` characters (bytes) with `fill` on the right.
string PadRight(StringSlice s, int width, char fill)
{
    if (s.Length >= width)
        return s.ToString();
    return s + Repeat(fill.ToString(), width - s.Length);
}

/// `s` with the ASCII letters in upper case.
string ToUpper(StringSlice s)
{
    var bytes = new uint8[s.Length];
    for (var i = 0; i < s.Length; i += 1)
    {
        char c = s[i];
        if (c >= 'a' && c <= 'z')
            c = (char)(c - 32);
        bytes[i] = c;
    }
    return string.FromBytes(bytes);
}

/// `s` with the ASCII letters in lower case.
string ToLower(StringSlice s)
{
    var bytes = new uint8[s.Length];
    for (var i = 0; i < s.Length; i += 1)
    {
        char c = s[i];
        if (c >= 'A' && c <= 'Z')
            c = (char)(c + 32);
        bytes[i] = c;
    }
    return string.FromBytes(bytes);
}

/// `s` with every occurrence of `oldValue` replaced by `newValue`.
/// @returns `s` unchanged if `oldValue` is empty.
string Replace(StringSlice s, StringSlice oldValue, StringSlice newValue)
{
    if (oldValue.Length == 0)
        return s.ToString();
    var result = StringBuilder.Create();
    int position = 0;
    while (true)
    {
        int found = IndexOf(s, oldValue, position);
        if (found < 0)
            break;
        result.Append(s[position..found]);
        result.Append(newValue);
        position = found + oldValue.Length;
    }
    result.Append(s[position..]);
    return result.ToString();
}

/// `s` repeated `count` times: `"ab".Repeat(3)` is `"ababab"`.
string Repeat(StringSlice s, int count)
{
    var result = StringBuilder.Create();
    for (var i = 0; i < count; i += 1)
        result.Append(s);
    return result.ToString();
}

// ---- Splitting and joining ----

/// The parts of `s` between the occurrences of `separator`, as views of `s` (nothing is copied):
/// `"a,,b".Split(",")` is `["a", "", "b"]`.
StringSlice[] Split(StringSlice s, StringSlice separator)
{
    if (separator.Length == 0)
    {
        var whole = new StringSlice[1];
        whole[0] = s;
        return whole;
    }

    int parts = 1;
    int position = IndexOf(s, separator, 0);
    while (position >= 0)
    {
        parts += 1;
        position = IndexOf(s, separator, position + separator.Length);
    }

    var result = new StringSlice[parts];
    int start = 0;
    for (var i = 0; i < parts - 1; i += 1)
    {
        int end = IndexOf(s, separator, start);
        result[i] = s[start..end];
        start = end + separator.Length;
    }
    result[parts - 1] = s[start..];
    return result;
}

/// The parts of `s` between the occurrences of the character `separator`, as views of `s`.
StringSlice[] Split(StringSlice s, char separator)
{
    int parts = 1;
    for (var i = 0; i < s.Length; i += 1)
    {
        if (s[i] == separator)
            parts += 1;
    }

    var result = new StringSlice[parts];
    int start = 0;
    int index = 0;
    for (var i = 0; i < s.Length; i += 1)
    {
        if (s[i] == separator)
        {
            result[index] = s[start..i];
            index += 1;
            start = i + 1;
        }
    }
    result[index] = s[start..];
    return result;
}

/// The `parts` joined into one string, with `separator` between them: `string.Join(", ", names)`.
string Join(StringSlice separator, string[] parts)
{
    var result = StringBuilder.Create();
    for (var i = 0; i < parts.Length; i += 1)
    {
        if (i > 0)
            result.Append(separator);
        result.Append(parts[i]);
    }
    return result.ToString();
}

/// The `parts` (e.g. the result of [String.Split]) joined into one string, with `separator` between them.
string Join(StringSlice separator, StringSlice[] parts)
{
    var result = StringBuilder.Create();
    for (var i = 0; i < parts.Length; i += 1)
    {
        if (i > 0)
            result.Append(separator);
        result.Append(parts[i]);
    }
    return result.ToString();
}

// ---- Parsing ----

/// The integer in `s`: decimal digits with an optional `+` or `-` sign, nothing else (no spaces).
/// @error ParseError.Invalid `s` is not an integer.
/// @error ParseError.OutOfRange the number does not fit into an `int64`.
ParseError<int64> ParseInt64(StringSlice s)
{
    int n = s.Length;
    int i = 0;
    bool negative = false;
    if (n > 0 && (s[0] == '-' || s[0] == '+'))
    {
        negative = s[0] == '-';
        i = 1;
    }
    if (i >= n)
        return error("invalid number '" + s + "'", ParseError.Invalid);

    // Accumulate as a negative number so that int64.MinValue can be parsed.
    int64 value = 0;
    while (i < n)
    {
        char c = s[i];
        if (c < '0' || c > '9')
            return error("invalid number '" + s + "'", ParseError.Invalid);
        int digit = c - '0';
        if (value < (int64.MinValue + digit) / 10)
            return error("number out of range '" + s + "'", ParseError.OutOfRange);
        value = value * 10 - digit;
        i += 1;
    }
    if (!negative)
    {
        if (value == int64.MinValue)
            return error("number out of range '" + s + "'", ParseError.OutOfRange);
        value = -value;
    }
    return value;
}

/// The integer in `s`: decimal digits with an optional `+` or `-` sign, nothing else (no spaces).
/// @error ParseError.Invalid `s` is not an integer.
/// @error ParseError.OutOfRange the number does not fit into an `int`.
ParseError<int> ParseInt(StringSlice s)
{
    var value = try ParseInt64(s);
    if (value < int.MinValue || value > int.MaxValue)
        return error("number out of range '" + s + "'", ParseError.OutOfRange);
    return (int)value;
}

/// The floating point number in `s` (`"3.5"`, `"-1e-3"`, `"inf"`, ...; the C library's `strtod`, without spaces
/// around it).
/// @error ParseError.Invalid `s` is not a number.
ParseError<double> ParseDouble(StringSlice s)
{
    if (s.Length == 0)
        return error("invalid number ''", ParseError.Invalid);
    string text = s.ToString(); // strtod needs the terminating NUL of a string
    unsafe
    {
        char* start = text.CStr();
        char* end = start;
        double value = strtod(start, &end);
        if (end == start || *end != 0)
            return error("invalid number '" + s + "'", ParseError.Invalid);
        return value;
    }
}
