// String helpers. The compiler forwards unknown string methods to this namespace:
//
//     "a,b".Contains(",")      is    String.Contains("a,b", ",")
//     string.Join(", ", parts) is    String.Join(", ", parts)
//
// Strings are UTF-8. Positions and lengths are byte offsets (like string.Length and s[i]).
// Case conversion only handles ASCII letters.

namespace String;

using System.Native;

bool IsNullOrEmpty(string s)
{
    return s == null || s.Length == 0;
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
int IndexOf(string s, string value, int start)
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

int IndexOf(string s, string value)
{
    return IndexOf(s, value, 0);
}

int IndexOf(string s, char value)
{
    for (var i = 0; i < s.Length; i += 1)
    {
        if (s[i] == value)
            return i;
    }
    return -1;
}

int LastIndexOf(string s, char value)
{
    for (var i = s.Length - 1; i >= 0; i -= 1)
    {
        if (s[i] == value)
            return i;
    }
    return -1;
}

bool Contains(string s, string value)
{
    return IndexOf(s, value, 0) >= 0;
}

bool Contains(string s, char value)
{
    return IndexOf(s, value) >= 0;
}

bool StartsWith(string s, string prefix)
{
    if (prefix.Length > s.Length)
        return false;
    for (var i = 0; i < prefix.Length; i += 1)
    {
        if (s[i] != prefix[i])
            return false;
    }
    return true;
}

bool EndsWith(string s, string suffix)
{
    int offset = s.Length - suffix.Length;
    if (offset < 0)
        return false;
    for (var i = 0; i < suffix.Length; i += 1)
    {
        if (s[offset + i] != suffix[i])
            return false;
    }
    return true;
}

// ---- Transforming ----

bool IsSpace(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

string Trim(string s)
{
    int start = 0;
    int end = s.Length;
    while (start < end && IsSpace(s[start]))
        start += 1;
    while (end > start && IsSpace(s[end - 1]))
        end -= 1;
    return s.Substring(start, end - start);
}

string ToUpper(string s)
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

string ToLower(string s)
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

string Replace(string s, string oldValue, string newValue)
{
    if (oldValue.Length == 0)
        return s;
    string result = "";
    int position = 0;
    while (true)
    {
        int found = IndexOf(s, oldValue, position);
        if (found < 0)
            break;
        result += s.Substring(position, found - position);
        result += newValue;
        position = found + oldValue.Length;
    }
    return result + s.Substring(position);
}

string Repeat(string s, int count)
{
    string result = "";
    for (var i = 0; i < count; i += 1)
        result += s;
    return result;
}

// ---- Splitting and joining ----

string[] Split(string s, string separator)
{
    if (separator.Length == 0)
        return new string[] { s };

    int parts = 1;
    int position = IndexOf(s, separator, 0);
    while (position >= 0)
    {
        parts += 1;
        position = IndexOf(s, separator, position + separator.Length);
    }

    var result = new string[parts];
    int start = 0;
    for (var i = 0; i < parts - 1; i += 1)
    {
        int end = IndexOf(s, separator, start);
        result[i] = s.Substring(start, end - start);
        start = end + separator.Length;
    }
    result[parts - 1] = s.Substring(start);
    return result;
}

string[] Split(string s, char separator)
{
    int parts = 1;
    for (var i = 0; i < s.Length; i += 1)
    {
        if (s[i] == separator)
            parts += 1;
    }

    var result = new string[parts];
    int start = 0;
    int index = 0;
    for (var i = 0; i < s.Length; i += 1)
    {
        if (s[i] == separator)
        {
            result[index] = s.Substring(start, i - start);
            index += 1;
            start = i + 1;
        }
    }
    result[index] = s.Substring(start);
    return result;
}

string Join(string separator, string[] parts)
{
    string result = "";
    for (var i = 0; i < parts.Length; i += 1)
    {
        if (i > 0)
            result += separator;
        result += parts[i];
    }
    return result;
}

// ---- Parsing ----

Error<int64> ParseInt64(string s)
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
        return error("invalid number '" + s + "'");

    // Accumulate as a negative number so that int64.MinValue can be parsed.
    int64 value = 0;
    while (i < n)
    {
        char c = s[i];
        if (c < '0' || c > '9')
            return error("invalid number '" + s + "'");
        int digit = c - '0';
        if (value < (int64.MinValue + digit) / 10)
            return error("number out of range '" + s + "'");
        value = value * 10 - digit;
        i += 1;
    }
    if (!negative)
    {
        if (value == int64.MinValue)
            return error("number out of range '" + s + "'");
        value = -value;
    }
    return value;
}

Error<int> ParseInt(string s)
{
    var value = try ParseInt64(s);
    if (value < int.MinValue || value > int.MaxValue)
        return error("number out of range '" + s + "'");
    return (int)value;
}

Error<double> ParseDouble(string s)
{
    if (s.Length == 0)
        return error("invalid number ''");
    unsafe
    {
        char* start = s.CStr();
        char* end = start;
        double value = strtod(start, &end);
        if (end == start || *end != 0)
            return error("invalid number '" + s + "'");
        return value;
    }
}
