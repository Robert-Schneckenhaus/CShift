// The C library's number functions for the 68000 without an FPU: strtod and the rounding functions, sqrt and fabs,
// exact on integers (the transcendental functions are in mathtrans.csh). The functions replace those of a C library
// (they have its names), whose floating point may use an FPU the program does not have.
//
// Part of the runtime of the m68k backend (added to the program only when that backend is used).

namespace System.M68k;

const double _ToInt = 4503599627370496.0; // 2^52: x + 2^52 - 2^52 rounds x to an integer

// ---------------------------------------------------------------------------
// Rounding to integers (after musl)
// ---------------------------------------------------------------------------

double _TruncDouble(double x)
{
    unchecked
    {
        uint64 u = _DoubleToBits(x);
        if (_Exp64(u) == 2047)
            return x + x; // a NaN comes back quiet
        int e = _Exp64(u) - 1023 + 12;
        if (e >= 52 + 12)
            return x;
        if (e < 12)
            e = 1;
        uint64 m = 18446744073709551615ul >> e;
        if ((u & m) == 0ul)
            return x;
        return _BitsToDouble(u & ~m);
    }
}

double _FloorDouble(double x)
{
    uint64 u = _DoubleToBits(x);
    int e = _Exp64(u);
    if (e == 2047)
        return x + x;
    if (e >= 1023 + 52 || x == 0.0)
        return x;
    // y = int(x) - x, where int(x) is an integer neighbour of x
    double y;
    if (_Sign64(u) != 0)
        y = x - _ToInt + _ToInt - x;
    else
        y = x + _ToInt - _ToInt - x;
    if (e <= 1023 - 1)
        return _Sign64(u) != 0 ? -1.0 : 0.0;
    if (y > 0.0)
        return x + y - 1.0;
    return x + y;
}

extern "C" double ceil(double x)
{
    uint64 u = _DoubleToBits(x);
    int e = _Exp64(u);
    if (e == 2047)
        return x + x;
    if (e >= 1023 + 52 || x == 0.0)
        return x;
    double y;
    if (_Sign64(u) != 0)
        y = x - _ToInt + _ToInt - x;
    else
        y = x + _ToInt - _ToInt - x;
    if (e <= 1023 - 1)
        return _Sign64(u) != 0 ? -0.0 : 1.0;
    if (y < 0.0)
        return x + y + 1.0;
    return x + y;
}

// to the nearest integer, ties to even
extern "C" double nearbyint(double x)
{
    uint64 u = _DoubleToBits(x);
    if (_Exp64(u) == 2047)
        return x + x;
    if (_Exp64(u) >= 1023 + 52)
        return x;
    double y;
    if (_Sign64(u) != 0)
        y = x - _ToInt + _ToInt;
    else
        y = x + _ToInt - _ToInt;
    if (y == 0.0)
        return _Sign64(u) != 0 ? -0.0 : 0.0;
    return y;
}

extern "C" double rint(double x) { return nearbyint(x); }

// to the nearest integer, ties away from zero
extern "C" double round(double x)
{
    double t = _TruncDouble(x);
    double d = x - t;
    if (d >= 0.5)
        return t + 1.0;
    if (d <= -0.5)
        return t - 1.0;
    return t;
}

double _FabsDouble(double x)
{
    unchecked
    {
        return _BitsToDouble(_DoubleToBits(x) & 9223372036854775807ul);
    }
}

extern "C" double floor(double x) { return _FloorDouble(x); }
extern "C" double fabs(double x) { return _FabsDouble(x); }
extern "C" double trunc(double x) { return _TruncDouble(x); }

extern "C" float fabsf(float x)
{
    unchecked
    {
        return _BitsToFloat(_FloatToBits(x) & 2147483647u);
    }
}

extern "C" float floorf(float x) { return __truncdfsf2(_FloorDouble(__extendsfdf2(x))); }
extern "C" float ceilf(float x) { return __truncdfsf2(ceil(__extendsfdf2(x))); }
extern "C" float truncf(float x) { return __truncdfsf2(_TruncDouble(__extendsfdf2(x))); }
extern "C" float roundf(float x) { return __truncdfsf2(round(__extendsfdf2(x))); }

// ---------------------------------------------------------------------------
// _Square root: bit by bit, correctly rounded (after fdlibm)
// ---------------------------------------------------------------------------

double _SqrtDouble(double x)
{
    unchecked
    {
        uint64 u = _DoubleToBits(x);
        int e = _Exp64(u);
        uint64 sig = _Frac64(u);
        if (e == 2047)
        {
            if (sig != 0ul || _Sign64(u) == 0)
                return x; // NaN, +infinity
            return _BitsToDouble(_DefaultNaN);
        }
        if (e == 0 && sig == 0ul)
            return x; // +0, -0
        if (_Sign64(u) != 0)
            return _BitsToDouble(_DefaultNaN);
        if (e == 0)
            sig = _NormalizeSubnormal64(sig, ref e);
        else
            sig = sig | 4503599627370496ul;
        // x = sig * 2^(m - 52): make m even
        int m = e - 1023;
        if ((m & 1) != 0)
        {
            sig = sig + sig;
            m -= 1;
        }
        m = m / 2;
        sig = sig + sig;
        uint64 q = 0ul;
        uint64 s = 0ul;
        uint64 r = 9007199254740992ul; // 2^53
        while (r != 0ul)
        {
            uint64 t = s + r;
            if (t <= sig)
            {
                s = t + r;
                sig = sig - t;
                q = q + r;
            }
            sig = sig + sig;
            r = r >> 1;
        }
        // q has one bit below the result: round to nearest (a tie cannot happen)
        if (sig != 0ul)
            q = q + (q & 1ul);
        uint64 bits = (q >> 1) + ((uint64)(1022 + m) << 52);
        return _BitsToDouble(bits);
    }
}

// double has more than twice the bits of float plus two: rounding the double root once more gives the float root
extern "C" float sqrtf(float x) { return __truncdfsf2(_SqrtDouble(__extendsfdf2(x))); }
extern "C" double sqrt(double x) { return _SqrtDouble(x); }

// ---------------------------------------------------------------------------
// strtod: decimal text to the nearest double (big integers, correctly rounded)
// ---------------------------------------------------------------------------

// Big natural numbers: 32-bit limbs, the lowest first, without leading zero limbs.
List<uint32> _BigOf(uint32 value)
{
    var a = List<uint32>.Create();
    if (value != 0u)
        a.Add(value);
    return a;
}

void _BigMulAdd(List<uint32> a, uint32 factor, uint32 add)
{
    unchecked
    {
        uint64 carry = (uint64)add;
        for (var i = 0; i < a.Count(); i += 1)
        {
            uint64 v = (uint64)a.Get(i) * (uint64)factor + carry;
            a.Set(i, (uint32)v);
            carry = v >> 32;
        }
        if (carry != 0ul)
            a.Add((uint32)carry);
    }
}

int _BigBits(List<uint32> a)
{
    int n = a.Count();
    if (n == 0)
        return 0;
    uint32 top = a.Get(n - 1);
    int bits = 0;
    while (top != 0u)
    {
        bits += 1;
        top = top >> 1;
    }
    return (n - 1) * 32 + bits;
}

List<uint32> _BigShiftLeft(List<uint32> a, int count)
{
    unchecked
    {
        var r = List<uint32>.Create();
        if (a.Count() == 0)
            return r;
        int limbs = count / 32;
        int bits = count % 32;
        for (var i = 0; i < limbs; i += 1)
            r.Add(0u);
        uint32 carry = 0u;
        for (var i = 0; i < a.Count(); i += 1)
        {
            uint32 v = a.Get(i);
            if (bits == 0)
                r.Add(v);
            else
            {
                r.Add((v << bits) | carry);
                carry = v >> (32 - bits);
            }
        }
        if (carry != 0u)
            r.Add(carry);
        return r;
    }
}

int _BigCompare(List<uint32> a, List<uint32> b)
{
    if (a.Count() != b.Count())
        return a.Count() < b.Count() ? -1 : 1;
    for (var i = a.Count() - 1; i >= 0; i -= 1)
    {
        uint32 x = a.Get(i);
        uint32 y = b.Get(i);
        if (x != y)
            return x < y ? -1 : 1;
    }
    return 0;
}

// a -= b (a >= b)
void _BigSub(List<uint32> a, List<uint32> b)
{
    unchecked
    {
        int64 borrow = 0;
        for (var i = 0; i < a.Count(); i += 1)
        {
            int64 v = (int64)a.Get(i) - borrow;
            if (i < b.Count())
                v -= (int64)b.Get(i);
            borrow = 0;
            if (v < 0)
            {
                v += 4294967296;
                borrow = 1;
            }
            a.Set(i, (uint32)v);
        }
        while (a.Count() > 0 && a.Get(a.Count() - 1) == 0u)
            a.RemoveAt(a.Count() - 1);
    }
}

// the highest 63 bits of a (a has at least 63 bits), the lower bits jammed into the lowest bit
uint64 _BigTop63(List<uint32> a)
{
    unchecked
    {
        int bits = _BigBits(a);
        int shift = bits - 63;
        uint64 r = 0ul;
        bool lost = false;
        for (var i = a.Count() - 1; i >= 0; i -= 1)
        {
            uint64 limb = (uint64)a.Get(i);
            int pos = i * 32 - shift; // where bit 0 of the limb lands
            if (pos >= 0)
                r = r | (limb << pos);
            else if (pos > -32)
            {
                r = r | (limb >> -pos);
                if ((limb << (64 + pos)) != 0ul)
                    lost = true;
            }
            else if (limb != 0ul)
                lost = true;
        }
        return r | (lost ? 1ul : 0ul);
    }
}

bool _IsSpace(int c) { return c == 32 || (c >= 9 && c <= 13); }
int _Lower(int c) { return c >= 65 && c <= 90 ? c + 32 : c; }

// the letters of word (lower case) at text, in any case
bool _MatchWord(char* text, string word)
{
    unsafe
    {
        for (var i = 0; i < word.Length; i += 1)
        {
            if (_Lower((int)*(text + i)) != (int)word[i])
                return false;
        }
        return true;
    }
}

const int _MaxDigits = 800; // more digits than any double needs to be rounded right; the rest only count as non-zero

extern "C" double strtod(char* text, char** end)
{
    unsafe
    {
        char* p = text;
        while (_IsSpace((int)*p))
            p = p + 1;
        int sign = 0;
        if (*p == 45)
        {
            sign = 1;
            p = p + 1;
        }
        else if (*p == 43)
            p = p + 1;
        if (_MatchWord(p, "inf"))
        {
            p = p + (_MatchWord(p, "infinity") ? 8 : 3);
            if (end != null)
                *end = p;
            return _BitsToDouble(_Pack64(sign, 2047, 0ul));
        }
        if (_MatchWord(p, "nan"))
        {
            p = p + 3;
            if (*p == 40)
            {
                char* q = p + 1;
                while (*q != 0 && *q != 41)
                    q = q + 1;
                if (*q == 41)
                    p = q + 1;
            }
            if (end != null)
                *end = p;
            return _BitsToDouble(9221120237041090560ul); // 0x7FF8000000000000
        }

        if (*p == 48 && _Lower((int)*(p + 1)) == 120 && (_HexDigit((int)*(p + 2)) >= 0 || (*(p + 2) == 46 && _HexDigit((int)*(p + 3)) >= 0)))
            return _ParseHex(sign, p + 2, end);

        // the digits: value = digits * 10^exp10
        var digits = _BigOf(0u);
        int count = 0;       // significant digits in 'digits'
        int exp10 = 0;
        bool any = false;    // a digit was seen
        bool dropped = false;
        bool point = false;
        while (true)
        {
            int c = (int)*p;
            if (c >= 48 && c <= 57)
            {
                any = true;
                if (count == 0 && c == 48)
                {
                    if (point)
                        exp10 -= 1;
                }
                else if (count < _MaxDigits)
                {
                    _BigMulAdd(digits, 10u, (uint32)(c - 48));
                    count += 1;
                    if (point)
                        exp10 -= 1;
                }
                else
                {
                    if (c != 48)
                        dropped = true;
                    if (!point)
                        exp10 += 1;
                }
            }
            else if (c == 46 && !point)
                point = true;
            else
                break;
            p = p + 1;
        }
        if (!any)
        {
            if (end != null)
                *end = text;
            return 0.0;
        }
        int ec = _Lower((int)*p);
        if (ec == 101)
        {
            char* q = p + 1;
            int esign = 1;
            if (*q == 45)
            {
                esign = -1;
                q = q + 1;
            }
            else if (*q == 43)
                q = q + 1;
            if ((int)*q >= 48 && (int)*q <= 57)
            {
                int e = 0;
                while ((int)*q >= 48 && (int)*q <= 57)
                {
                    if (e < 100000)
                        e = e * 10 + ((int)*q - 48);
                    q = q + 1;
                }
                exp10 += esign * e;
                p = q;
            }
        }
        if (end != null)
            *end = p;
        return _BitsToDouble(_DecimalToDouble(sign, digits, count, exp10, dropped));
    }
}

int _HexDigit(int c)
{
    if (c >= 48 && c <= 57)
        return c - 48;
    int l = _Lower(c);
    if (l >= 97 && l <= 102)
        return l - 87;
    return -1;
}

// the text after "0x": hex digits with an optional point, and an optional binary exponent p[+-]digits
double _ParseHex(int sign, char* p, char** end)
{
    unsafe
    {
        unchecked
        {
            uint64 sig = 0ul;
            int exp2 = 0;
            bool sticky = false;
            bool point = false;
            while (true)
            {
                int d = _HexDigit((int)*p);
                if (d >= 0)
                {
                    if ((sig >> 58) == 0ul)
                    {
                        sig = (sig << 4) | (uint64)d;
                        if (point)
                            exp2 -= 4;
                    }
                    else
                    {
                        if (d != 0)
                            sticky = true;
                        if (!point)
                            exp2 += 4;
                    }
                }
                else if (*p == 46 && !point)
                    point = true;
                else
                    break;
                p = p + 1;
            }
            if (_Lower((int)*p) == 112)
            {
                char* q = p + 1;
                int esign = 1;
                if (*q == 45)
                {
                    esign = -1;
                    q = q + 1;
                }
                else if (*q == 43)
                    q = q + 1;
                if ((int)*q >= 48 && (int)*q <= 57)
                {
                    int e = 0;
                    while ((int)*q >= 48 && (int)*q <= 57)
                    {
                        if (e < 100000)
                            e = e * 10 + ((int)*q - 48);
                        q = q + 1;
                    }
                    exp2 += esign * e;
                    p = q;
                }
            }
            if (end != null)
                *end = p;
            if (sig == 0ul)
                return _BitsToDouble(_Pack64(sign, 0, 0ul));
            if (exp2 > 2000)
                return _BitsToDouble(_Pack64(sign, 2047, 0ul));
            if (exp2 < -2200)
                return _BitsToDouble(_Pack64(sign, 0, 0ul));
            // value = sig * 2^exp2 = sig * 2^(exp - 1084)
            return _BitsToDouble(_NormalizeRoundPack64(sign, exp2 + 1084, sig | (sticky ? 1ul : 0ul)));
        }
    }
}

uint64 _DecimalToDouble(int sign, List<uint32> digits, int count, int exp10, bool dropped)
{
    unchecked
    {
        if (count == 0)
            return _Pack64(sign, 0, 0ul);
        if (count + exp10 > 310)
            return _Pack64(sign, 2047, 0ul);
        if (count + exp10 < -325)
            return _Pack64(sign, 0, 0ul);
        if (dropped)
        {
            // a non-zero digit after the kept ones: one more digit 1 has the same effect on the rounding
            _BigMulAdd(digits, 10u, 1u);
            exp10 -= 1;
        }
        if (exp10 >= 0)
        {
            for (var i = 0; i < exp10; i += 1)
                _BigMulAdd(digits, 10u, 0u);
            int bits = _BigBits(digits);
            if (bits < 63)
                return _RoundPack64(sign, bits - 63 + 1084, _BigTop63(_BigShiftLeft(digits, 63 - bits)));
            return _RoundPack64(sign, bits - 63 + 1084, _BigTop63(digits));
        }
        // digits / 10^-exp10: 64 quotient bits by long division
        var den = _BigOf(1u);
        for (var i = 0; i < -exp10; i += 1)
            _BigMulAdd(den, 10u, 0u);
        int s = 63 - _BigBits(digits) + _BigBits(den); // digits * 2^s / den lies in [2^62, 2^64)
        var num = s >= 0 ? _BigShiftLeft(digits, s) : digits;
        if (s < 0)
            den = _BigShiftLeft(den, -s);
        uint64 q = 0ul;
        for (var bit = 63; bit >= 0; bit -= 1)
        {
            var t = _BigShiftLeft(den, bit);
            if (_BigCompare(num, t) >= 0)
            {
                _BigSub(num, t);
                q = q | (1ul << bit);
            }
        }
        uint64 sticky = num.Count() > 0 ? 1ul : 0ul;
        if ((q >> 63) != 0ul)
        {
            sticky = sticky | (q & 1ul);
            q = q >> 1;
            s -= 1;
        }
        return _RoundPack64(sign, 1084 - s, q | sticky);
    }
}

extern "C" float strtof(char* text, char** end) { return __truncdfsf2(strtod(text, end)); }

extern "C" double atof(char* text)
{
    unsafe
    {
        return strtod(text, null);
    }
}
