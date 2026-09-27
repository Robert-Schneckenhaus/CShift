// Number formats: value.ToString("F2") and $"{value:F2}" (the compiler calls these functions).
//
//     D[n]  integers: at least n digits, filled with zeros               42.ToString("D5")        "00042"
//     X[n]  integers: hexadecimal (x: lower case), at least n digits     255.ToString("X4")       "00FF"
//     B[n]  integers: binary, at least n digits                          5.ToString("B8")         "00000101"
//     F[n]  fixed point with n decimals (default 2)                      3.14159.ToString("F2")   "3.14"
//     N[n]  like F with ',' between groups of thousands                  1234567.ToString("N0")   "1,234,567"
//     E[n]  scientific, n decimals (default 6; e: lower case)            1234.5.ToString("E2")    "1.23E+003"
//     P[n]  percent: times 100, n decimals (default 2)                   0.256.ToString("P1")     "25.6 %"
//     G     the same text as ToString()
//
// The text does not depend on the platform or a locale ('.' and ','). Floating point values are formatted from their
// exact binary value and rounded half away from zero, like .NET: 0.125.ToString("F2") is "0.13", 2.5.ToString("F0")
// is "3". A result that is zero has no minus sign. Negative values in X and B are written in two's complement of the
// type's size ((-1).ToString("X") of an int32 is "FFFFFFFF").

namespace NumberFormat;

using System;

// The format of a letter and an optional number (precision); Letter is 0 if the text is not a valid format.
struct _Spec
{
    char Letter;       // upper case
    bool Lower;        // x, e: lower case letters in the result
    int Precision;     // -1 = not given
}

_Spec _Parse(string format)
{
    var spec = _Spec { Letter = (char)0, Precision = -1 };
    if (format.Length == 0 || format.Length > 3)
        return spec;
    char c = format[0];
    bool lower = c >= 'a' && c <= 'z';
    char upper = lower ? (char)((int)c - 32) : c;
    int precision = -1;
    for (var i = 1; i < format.Length; i += 1)
    {
        if (format[i] < '0' || format[i] > '9')
            return spec;
        precision = (precision < 0 ? 0 : precision * 10) + ((int)format[i] - (int)'0');
    }
    switch (upper)
    {
    case 'D':
    case 'X':
    case 'B':
    case 'F':
    case 'N':
    case 'E':
    case 'P':
        break;
    case 'G':
        if (precision >= 0)
            return spec;
        break;
    default:
        return spec;
    }
    spec.Letter = upper;
    spec.Lower = lower;
    spec.Precision = precision;
    return spec;
}

// "" if the format is valid for integers (floatingPoint false) or floating point numbers, otherwise why it is not.
// The compiler uses it to check a format that is written as a string literal.
string Check(string format, bool floatingPoint)
{
    var spec = _Parse(format);
    if (spec.Letter == (char)0)
        return "'" + format + "' is not a number format (D, X, B, F, N, E, P or G, optionally followed by up to two digits; G takes none)";
    if (floatingPoint && (spec.Letter == 'D' || spec.Letter == 'X' || spec.Letter == 'B'))
        return "the number format '" + format + "' is only for integers";
    return "";
}

// ---- integers ----

string FormatInt(int64 value, int bits, string format)
{
    var spec = _Parse(format);
    if (spec.Letter == (char)0)
        Environment.Panic("invalid number format '" + format + "' for an integer");
    if (spec.Letter == 'X' || spec.Letter == 'B')
    {
        uint64 raw = unchecked((uint64)value);
        if (bits < 64)
            raw &= (unchecked((uint64)1) << bits) - 1;
        return _Radix(raw, spec);
    }
    bool negative = value < 0;
    uint64 magnitude = negative ? unchecked((uint64)(-(value + 1))) + 1 : (uint64)value;
    return _Integer(negative, magnitude, spec, value.ToString());
}

string FormatUInt(uint64 value, int bits, string format)
{
    var spec = _Parse(format);
    if (spec.Letter == (char)0)
        Environment.Panic("invalid number format '" + format + "' for an integer");
    if (spec.Letter == 'X' || spec.Letter == 'B')
        return _Radix(value, spec);
    return _Integer(false, value, spec, value.ToString());
}

string _Radix(uint64 value, _Spec spec)
{
    int shift = spec.Letter == 'X' ? 4 : 1;
    uint64 mask = spec.Letter == 'X' ? (uint64)15 : (uint64)1;
    string letters = spec.Lower ? "0123456789abcdef" : "0123456789ABCDEF";
    var digits = StringBuilder.Create();
    uint64 rest = value;
    do
    {
        digits.Append(letters[(int)(rest & mask)]);
        rest >>= shift;
    } while (rest != 0);
    return _Reverse(digits.ToString(), spec.Precision);
}

// The digits in reverse order, filled with zeros up to 'minimum' characters.
string _Reverse(string reversed, int minimum)
{
    var sb = StringBuilder.Create();
    for (var i = reversed.Length; i < minimum; i += 1)
        sb.Append('0');
    for (var i = reversed.Length - 1; i >= 0; i -= 1)
        sb.Append(reversed[i]);
    return sb.ToString();
}

string _Integer(bool negative, uint64 magnitude, _Spec spec, string plain)
{
    if (spec.Letter == 'G')
        return plain;
    string digits = magnitude.ToString();
    if (spec.Letter == 'D')
    {
        var sb = StringBuilder.Create();
        if (negative)
            sb.Append('-');
        for (var i = digits.Length; i < spec.Precision; i += 1)
            sb.Append('0');
        sb.Append(digits);
        return sb.ToString();
    }
    return _Decimal(negative, digits, digits.Length, spec);
}

// ---- floating point ----

string FormatFloat(double value, bool single, string format)
{
    var spec = _Parse(format);
    if (spec.Letter == (char)0 || spec.Letter == 'D' || spec.Letter == 'X' || spec.Letter == 'B')
        Environment.Panic("invalid number format '" + format + "' for " + (single ? "float" : "double"));
    if (spec.Letter == 'G')
        return single ? ((float)value).ToString() : value.ToString();
    if (value != value)
        return "nan";
    if (value == double.PositiveInfinity)
        return spec.Letter == 'P' ? "inf %" : "inf";
    if (value == double.NegativeInfinity)
        return spec.Letter == 'P' ? "-inf %" : "-inf";

    uint64 bits = 0;
    unsafe
    {
        double copy = value;
        bits = *(uint64*)&copy;
    }
    bool negative = (bits >> 63) != 0;
    int exponent = (int)((bits >> 52) & 0x7FF);
    uint64 mantissa = bits & 0xFFFFFFFFFFFFF;
    if (exponent == 0)
        exponent = 1;                   // subnormal
    else
        mantissa |= unchecked((uint64)1) << 52;
    exponent -= 1075;                   // value = mantissa * 2^exponent

    // the exact decimal digits: mantissa * 2^exponent, or mantissa * 5^-exponent with -exponent digits after the point
    var number = _Big.Create(mantissa);
    int fraction = 0;
    if (exponent >= 0)
    {
        for (var i = 0; i < exponent; i += 1)
            number.MultiplySmall(2);
    }
    else
    {
        fraction = -exponent;
        for (var i = 0; i < fraction; i += 13)
            number.MultiplySmall(i + 13 <= fraction ? 1220703125 : _PowerOf5(fraction - i)); // 5^13
    }
    string digits = number.ToString();
    return _Decimal(negative, digits, digits.Length - fraction, spec);
}

int64 _PowerOf5(int n)
{
    int64 p = 1;
    for (var i = 0; i < n; i += 1)
        p *= 5;
    return p;
}

// A non-negative integer in base 10^9, least significant limb first.
struct _Big
{
    List<int64> Limbs;

    static _Big Create(uint64 value)
    {
        var big = _Big { Limbs = List<int64>.Create() };
        uint64 rest = value;
        do
        {
            big.Limbs.Add((int64)(rest % 1000000000));
            rest /= 1000000000;
        } while (rest != 0);
        return big;
    }

    // factor < 2^31
    void MultiplySmall(int64 factor)
    {
        int64 carry = 0;
        for (var i = 0; i < Limbs.Count(); i += 1)
        {
            int64 product = Limbs.Get(i) * factor + carry;
            Limbs.Set(i, product % 1000000000);
            carry = product / 1000000000;
        }
        while (carry != 0)
        {
            Limbs.Add(carry % 1000000000);
            carry /= 1000000000;
        }
    }

    string ToString()
    {
        var sb = StringBuilder.Create();
        int top = Limbs.Count() - 1;
        sb.Append(Limbs.Get(top).ToString());
        for (var i = top - 1; i >= 0; i -= 1)
            sb.Append(Limbs.Get(i).ToString().PadLeft(9, '0'));
        return sb.ToString();
    }
}

// ---- F, N, E, P on exact decimal digits ----

// The number is 0.digits * 10^point (the first 'point' digits are the integer part; point may be negative or larger
// than the number of digits).
string _Decimal(bool negative, string digits, int point, _Spec spec)
{
    if (spec.Letter == 'E')
        return _Scientific(negative, digits, point, spec);
    if (spec.Letter == 'P')
        point += 2;
    int decimals = spec.Precision >= 0 ? spec.Precision : (spec.Letter == 'F' || spec.Letter == 'N' || spec.Letter == 'P' ? 2 : 0);
    // the number rounded to 'decimals' places, as an integer of units of 10^-decimals
    string kept = _Round(digits, point + decimals).Digits;
    while (kept.Length < decimals + 1)
        kept = "0" + kept;
    string intPart = kept.Substring(0, kept.Length - decimals);
    string fracPart = kept.Substring(kept.Length - decimals);
    int skip = 0;
    while (skip < intPart.Length - 1 && intPart[skip] == '0')
        skip += 1;
    intPart = intPart.Substring(skip);

    var sb = StringBuilder.Create();
    if (negative && !_AllZero(intPart + fracPart))
        sb.Append('-');
    if (spec.Letter == 'N')
    {
        for (var i = 0; i < intPart.Length; i += 1)
        {
            if (i > 0 && (intPart.Length - i) % 3 == 0)
                sb.Append(',');
            sb.Append(intPart[i]);
        }
    }
    else
        sb.Append(intPart);
    if (decimals > 0)
    {
        sb.Append('.');
        sb.Append(fracPart);
    }
    if (spec.Letter == 'P')
        sb.Append(" %");
    return sb.ToString();
}

struct _Rounded
{
    string Digits; // the kept digits (one more than asked for if rounding carried into a new leading digit)
    int Carry;     // 1 if a new leading digit was added
}

// The first 'count' digits, rounded half away from zero by the rest (count may be <= 0 or larger than the digits).
_Rounded _Round(string digits, int count)
{
    if (count < 0)
    {
        // everything is below the last kept place: rounds to zero, or up to 1 at that place only if it is at least
        // half of it, which a number below a tenth of it never is
        return _Rounded { Digits = "", Carry = 0 };
    }
    var kept = new char[count];
    for (var i = 0; i < count; i += 1)
        kept[i] = i < digits.Length ? digits[i] : '0';
    bool up = count < digits.Length && digits[count] >= '5';
    int carry = 0;
    if (up)
    {
        int i = count - 1;
        while (i >= 0 && kept[i] == '9')
        {
            kept[i] = '0';
            i -= 1;
        }
        if (i >= 0)
            kept[i] = (char)((int)kept[i] + 1);
        else
            carry = 1;
    }
    var sb = StringBuilder.Create();
    if (carry == 1)
        sb.Append('1');
    for (var i = 0; i < count; i += 1)
        sb.Append(kept[i]);
    return _Rounded { Digits = sb.ToString(), Carry = carry };
}

bool _AllZero(string digits)
{
    for (var i = 0; i < digits.Length; i += 1)
    {
        if (digits[i] != '0')
            return false;
    }
    return true;
}

string _Scientific(bool negative, string digits, int point, _Spec spec)
{
    int decimals = spec.Precision >= 0 ? spec.Precision : 6;
    // skip leading zeros: the first significant digit gives the exponent
    int first = 0;
    while (first < digits.Length && digits[first] == '0')
        first += 1;
    int exponent = 0;
    string mantissa;
    if (first == digits.Length)
        mantissa = "";                                        // zero
    else
    {
        string significant = digits.Substring(first);
        exponent = point - first - 1;
        var kept = _Round(significant, decimals + 1);
        mantissa = kept.Digits;
        if (kept.Carry == 1)
        {
            exponent += 1;
            mantissa = mantissa.Substring(0, decimals + 1);
        }
    }
    while (mantissa.Length < decimals + 1)
        mantissa += "0";
    var sb = StringBuilder.Create();
    if (negative && !_AllZero(mantissa))
        sb.Append('-');
    sb.Append(mantissa[0]);
    if (decimals > 0)
    {
        sb.Append('.');
        sb.Append(mantissa.Substring(1));
    }
    sb.Append(spec.Lower ? 'e' : 'E');
    sb.Append(exponent < 0 ? '-' : '+');
    int magnitude = exponent < 0 ? -exponent : exponent;
    sb.Append(magnitude.ToString().PadLeft(3, '0'));
    return sb.ToString();
}
