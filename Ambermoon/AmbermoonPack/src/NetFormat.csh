// Number texts as .NET writes them, so that the output is the same as the one of the original tool.
namespace AmbermoonPack;

using System;

// A float with the custom format "0.00" like .NET (invariant culture): the exact value is rounded to 7 significant
// digits first (half to even), and that decimal to 2 decimals (half away from zero).
string FormatFloat2(float value)
{
    if (value != value)
        return "NaN";
    if (value > 3.4e38f)
        return "Infinity";
    if (value < -3.4e38f)
        return "-Infinity";

    uint32 bits;
    unsafe
    {
        float v = value;
        bits = *(uint32*)&v;
    }
    bool negative = (bits >> 31) != 0;
    int biased = (int)((bits >> 23) & 0xff);
    uint64 mantissa = bits & 0x7fffff;
    if (biased != 0)
        mantissa |= 0x800000;
    else
        biased = 1; // subnormal
    int exponent = biased - 127 - 23; // value = mantissa * 2^exponent

    // the exact decimal digits: integer part and fractional part
    var digits = List<int>.Create();
    int pointPosition; // the number of digits before the decimal point
    if (mantissa == 0)
        return "0.00";
    if (exponent >= 0)
    {
        if (exponent > 39)
            return value.ToString("F2"); // far beyond what the tool prints (and exact anyway)
        _AppendDigits(ref digits, mantissa << exponent);
        pointPosition = digits.Count();
    }
    else
    {
        int k = -exponent;
        if (k > 59)
            return negative ? "-0.00" : "0.00"; // below 2^-36: rounds to 0.00
        uint64 integer = mantissa >> k;
        uint64 fraction = mantissa & (((uint64)1 << k) - 1);
        if (integer > 0)
            _AppendDigits(ref digits, integer);
        pointPosition = digits.Count();
        while (fraction != 0)
        {
            fraction *= 10;
            digits.Add((int)(fraction >> k));
            fraction &= ((uint64)1 << k) - 1;
        }
    }

    // round to 7 significant digits, half to even
    int first = 0;
    while (first < digits.Count() && digits[first] == 0)
        first += 1;
    int keep = first + 7; // digits before this index stay
    if (keep < digits.Count())
    {
        bool roundUp = false;
        if (digits[keep] > 5)
            roundUp = true;
        else if (digits[keep] == 5)
        {
            bool rest = false;
            for (var i = keep + 1; i < digits.Count(); i += 1)
            {
                if (digits[i] != 0)
                    rest = true;
            }
            roundUp = rest || (digits[keep - 1] % 2 == 1);
        }
        while (digits.Count() > keep)
            digits.RemoveAt(digits.Count() - 1);
        if (roundUp)
            _Increment(ref digits, ref pointPosition, keep - 1);
    }

    // round to 2 decimals, half away from zero
    int end = pointPosition + 2;
    if (end < digits.Count())
    {
        bool roundUp = digits[end] >= 5;
        while (digits.Count() > end)
            digits.RemoveAt(digits.Count() - 1);
        if (roundUp)
        {
            if (end == 0)
            {
                digits.Insert(0, 1);
                pointPosition += 1;
            }
            else
                _Increment(ref digits, ref pointPosition, end - 1);
        }
    }

    var text = StringBuilder.Create();
    if (negative)
        text.Append('-');
    if (pointPosition <= 0)
        text.Append('0');
    for (var i = 0; i < pointPosition; i += 1)
        text.Append((char)('0' + (i < digits.Count() ? digits[i] : 0)));
    text.Append('.');
    for (var i = pointPosition; i < pointPosition + 2; i += 1)
        text.Append((char)('0' + (i >= 0 && i < digits.Count() ? digits[i] : 0)));
    return text.ToString();
}

void _AppendDigits(ref List<int> digits, uint64 value)
{
    var reversed = List<int>.Create();
    while (value > 0)
    {
        reversed.Add((int)(value % 10));
        value /= 10;
    }
    for (var i = reversed.Count() - 1; i >= 0; i -= 1)
        digits.Add(reversed[i]);
}

// adds 1 at digit 'index' (with carry; a carry out of the first digit adds a digit in front)
void _Increment(ref List<int> digits, ref int pointPosition, int index)
{
    int i = index;
    while (i >= 0)
    {
        if (digits[i] < 9)
        {
            digits[i] = digits[i] + 1;
            return;
        }
        digits[i] = 0;
        i -= 1;
    }
    digits.Insert(0, 1);
    pointPosition += 1;
}
