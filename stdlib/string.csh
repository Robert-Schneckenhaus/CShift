// String helpers. The compiler forwards unknown string methods to this namespace:
//
//     "a,b".Contains(",")      is    String.Contains("a,b", ",")
//     string.Join(", ", parts) is    String.Join(", ", parts)
//
// The helpers take StringSlice (a string converts to one for free, and s[i..j] is one), so they work on parts of a
// string without copying; Trim and Split return slices as well. Copy a result with .ToString() to keep it as a string.
// Strings are UTF-8. Positions and lengths are byte offsets (like string.Length and s[i]).
// Case conversion only handles ASCII letters.

namespace String;

using System;
using System.Native;

bool IsNullOrEmpty(StringSlice s)
{
    return s.Length == 0; // a null string is an empty slice
}

// ---- IEquatable<string>, IHashable and IComparable<string> (used by generic containers) ----

bool Equals(string a, string b)
{
    return a == b;
}

// FNV-1a
int GetHashCode(string s)
{
    uint hash = 2166136261;
    for (var i = 0; i < s.Length; i += 1)
        hash = unchecked((hash ^ (uint)s[i]) * 16777619);
    return (int)hash;
}

// Ordinal comparison of the UTF-8 bytes: -1, 0 or 1.
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

// ---- Searching ----

// Index of the first occurrence of value at or after start, or -1.
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

int IndexOf(StringSlice s, StringSlice value)
{
    return IndexOf(s, value, 0);
}

int IndexOf(StringSlice s, char value)
{
    return IndexOf(s, value, 0);
}

// Index of the first occurrence of the character at or after start, or -1.
int IndexOf(StringSlice s, char value, int start)
{
    for (var i = start < 0 ? 0 : start; i < s.Length; i += 1)
    {
        if (s[i] == value)
            return i;
    }
    return -1;
}

int LastIndexOf(StringSlice s, char value)
{
    for (var i = s.Length - 1; i >= 0; i -= 1)
    {
        if (s[i] == value)
            return i;
    }
    return -1;
}

bool Contains(StringSlice s, StringSlice value)
{
    return IndexOf(s, value, 0) >= 0;
}

bool Contains(StringSlice s, char value)
{
    return IndexOf(s, value) >= 0;
}

bool StartsWith(StringSlice s, StringSlice prefix)
{
    return prefix.Length <= s.Length && s[..prefix.Length] == prefix;
}

bool EndsWith(StringSlice s, StringSlice suffix)
{
    return suffix.Length <= s.Length && s[s.Length - suffix.Length..] == suffix;
}

// ---- Transforming ----

// Part of a slice, as a view (string.Substring is built in and copies): s[start..], s[start..start + count].
StringSlice Substring(StringSlice s, int start)
{
    return s[start..];
}

StringSlice Substring(StringSlice s, int start, int count)
{
    return s[start..start + count];
}

bool IsSpace(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

// Without the white space at both ends (a view of s, nothing is copied).
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

// Without the white space at the start.
StringSlice TrimStart(StringSlice s)
{
    int start = 0;
    while (start < s.Length && IsSpace(s[start]))
        start += 1;
    return s[start..];
}

// Without the white space at the end.
StringSlice TrimEnd(StringSlice s)
{
    int end = s.Length;
    while (end > 0 && IsSpace(s[end - 1]))
        end -= 1;
    return s[..end];
}

// Without the given characters at the start / at the end: "007".TrimStart('0') is "7".
StringSlice TrimStart(StringSlice s, char c)
{
    int start = 0;
    while (start < s.Length && s[start] == c)
        start += 1;
    return s[start..];
}

StringSlice TrimEnd(StringSlice s, char c)
{
    int end = s.Length;
    while (end > 0 && s[end - 1] == c)
        end -= 1;
    return s[..end];
}

// Filled up to 'width' characters (bytes) with spaces or 'fill' on the left / on the right: "7".PadLeft(3, '0') is "007".
string PadLeft(StringSlice s, int width)
{
    return PadLeft(s, width, ' ');
}

string PadLeft(StringSlice s, int width, char fill)
{
    if (s.Length >= width)
        return s.ToString();
    return Repeat(fill.ToString(), width - s.Length) + s;
}

string PadRight(StringSlice s, int width)
{
    return PadRight(s, width, ' ');
}

string PadRight(StringSlice s, int width, char fill)
{
    if (s.Length >= width)
        return s.ToString();
    return s + Repeat(fill.ToString(), width - s.Length);
}

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

string Repeat(StringSlice s, int count)
{
    var result = StringBuilder.Create();
    for (var i = 0; i < count; i += 1)
        result.Append(s);
    return result.ToString();
}

// ---- Splitting and joining ----

// The parts between the separators, as views of s (nothing is copied).
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

// Joins slices, e.g. the parts of Split.
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

ParseError<int> ParseInt(StringSlice s)
{
    var value = try ParseInt64(s);
    if (value < int.MinValue || value > int.MaxValue)
        return error("number out of range '" + s + "'", ParseError.OutOfRange);
    return (int)value;
}

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
