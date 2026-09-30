// Floating point for CPUs without an FPU (the 68000): IEEE 754 double arithmetic on integers, after Berkeley SoftFloat
// (John R. Hauser; round to nearest even, NaN, infinities and subnormal numbers). float is computed in double and
// rounded once: for +, -, *, / that gives the correctly rounded float.
//
// Part of the runtime of the m68k backend (added to the program only when that backend is used): the functions have
// the names of GCC's libgcc, so the backend's calls (fadd -> __adddf3, ...) and C code find them.

namespace System.M68k;

// ---------------------------------------------------------------------------
// Bits
// ---------------------------------------------------------------------------

uint64 _DoubleToBits(double d)
{
    unsafe
    {
        double copy = d;
        return *(uint64*)&copy;
    }
}

double _BitsToDouble(uint64 b)
{
    unsafe
    {
        uint64 copy = b;
        return *(double*)&copy;
    }
}

uint32 _FloatToBits(float f)
{
    unsafe
    {
        float copy = f;
        return *(uint32*)&copy;
    }
}

float _BitsToFloat(uint32 b)
{
    unsafe
    {
        uint32 copy = b;
        return *(float*)&copy;
    }
}

const uint64 _FracMask = 4503599627370495ul;   // 2^52 - 1
const uint64 _DefaultNaN = 18444492273895866368ul; // 0xFFF8000000000000

uint64 _Frac64(uint64 a) { return a & _FracMask; }
int _Exp64(uint64 a) { return (int)((a >> 52) & 2047ul); }
int _Sign64(uint64 a) { return (int)(a >> 63); }

uint64 _Pack64(int sign, int exp, uint64 sig)
{
    unchecked
    {
        return ((uint64)sign << 63) + ((uint64)exp << 52) + sig;
    }
}

int _LeadingZeros64(uint64 a)
{
    if (a == 0ul)
        return 64;
    int n = 0;
    if ((a >> 32) == 0ul)
    {
        n += 32;
        a = a << 32;
    }
    if ((a >> 48) == 0ul)
    {
        n += 16;
        a = a << 16;
    }
    if ((a >> 56) == 0ul)
    {
        n += 8;
        a = a << 8;
    }
    while ((a >> 63) == 0ul)
    {
        n += 1;
        a = a << 1;
    }
    return n;
}

// a >> count, with the bits shifted out ORed into the lowest bit ("jamming").
uint64 _ShiftRightJam64(uint64 a, int count)
{
    if (count == 0)
        return a;
    if (count >= 64)
        return a != 0ul ? 1ul : 0ul;
    uint64 lost = a << (64 - count);
    return (a >> count) | (lost != 0ul ? 1ul : 0ul);
}

// ---------------------------------------------------------------------------
// Rounding and packing (the significand has its leading bit at bit 62, 10 bits below the result's lowest bit)
// ---------------------------------------------------------------------------

uint64 _RoundPack64(int sign, int exp, uint64 sig)
{
    unchecked
    {
        uint64 roundBits = sig & 1023ul;
        if (exp >= 2045)
        {
            if (exp > 2045 || (exp == 2045 && (int64)(sig + 512ul) < 0))
                return _Pack64(sign, 2047, 0ul); // overflow: infinity
        }
        if (exp < 0)
        {
            sig = _ShiftRightJam64(sig, -exp);
            exp = 0;
            roundBits = sig & 1023ul;
        }
        sig = (sig + 512ul) >> 10;
        if (roundBits == 512ul)
            sig = sig & ~1ul; // a tie: to even
        if (sig == 0ul)
            exp = 0;
        return _Pack64(sign, exp, sig);
    }
}

uint64 _NormalizeRoundPack64(int sign, int exp, uint64 sig)
{
    int shift = _LeadingZeros64(sig) - 1;
    return _RoundPack64(sign, exp - shift, sig << shift);
}

// a subnormal significand: normalized, with its exponent
uint64 _NormalizeSubnormal64(uint64 sig, ref int exp)
{
    int shift = _LeadingZeros64(sig) - 11;
    exp = 1 - shift;
    return sig << shift;
}

bool _IsNaN64(uint64 a)
{
    return _Exp64(a) == 2047 && _Frac64(a) != 0ul;
}

// a NaN operand makes the result a (quiet) NaN
uint64 _PropagateNaN64(uint64 a, uint64 b)
{
    if (_IsNaN64(a))
        return a | 2251799813685248ul; // the quiet bit
    return b | 2251799813685248ul;
}

// ---------------------------------------------------------------------------
// Addition and subtraction
// ---------------------------------------------------------------------------

uint64 _AddSigs64(uint64 a, uint64 b, int sign)
{
    unchecked
    {
        uint64 aSig = _Frac64(a) << 9;
        uint64 bSig = _Frac64(b) << 9;
        int aExp = _Exp64(a);
        int bExp = _Exp64(b);
        int diff = aExp - bExp;
        int exp;
        uint64 sig;
        const uint64 hidden = 2305843009213693952ul; // 2^61
        if (diff > 0)
        {
            if (aExp == 2047)
                return aSig != 0ul ? _PropagateNaN64(a, b) : a;
            if (bExp == 0)
                diff -= 1;
            else
                bSig = bSig | hidden;
            bSig = _ShiftRightJam64(bSig, diff);
            exp = aExp;
        }
        else if (diff < 0)
        {
            if (bExp == 2047)
                return bSig != 0ul ? _PropagateNaN64(a, b) : _Pack64(sign, 2047, 0ul);
            if (aExp == 0)
                diff += 1;
            else
                aSig = aSig | hidden;
            aSig = _ShiftRightJam64(aSig, -diff);
            exp = bExp;
        }
        else
        {
            if (aExp == 2047)
                return (aSig | bSig) != 0ul ? _PropagateNaN64(a, b) : a;
            if (aExp == 0)
                return _Pack64(sign, 0, (aSig + bSig) >> 9);
            sig = 4611686018427387904ul + aSig + bSig; // 2^62
            return _RoundPack64(sign, aExp, sig);
        }
        aSig = aSig | hidden;
        sig = (aSig + bSig) << 1;
        exp -= 1;
        if ((int64)sig < 0)
        {
            sig = aSig + bSig;
            exp += 1;
        }
        return _RoundPack64(sign, exp, sig);
    }
}

uint64 _SubSigs64(uint64 a, uint64 b, int sign)
{
    unchecked
    {
        uint64 aSig = _Frac64(a) << 10;
        uint64 bSig = _Frac64(b) << 10;
        int aExp = _Exp64(a);
        int bExp = _Exp64(b);
        int diff = aExp - bExp;
        const uint64 hidden = 4611686018427387904ul; // 2^62
        if (diff > 0)
        {
            if (aExp == 2047)
                return aSig != 0ul ? _PropagateNaN64(a, b) : a;
            if (bExp == 0)
                diff -= 1;
            else
                bSig = bSig | hidden;
            bSig = _ShiftRightJam64(bSig, diff);
            aSig = aSig | hidden;
            return _NormalizeRoundPack64(sign, aExp - 1, aSig - bSig);
        }
        if (diff < 0)
        {
            if (bExp == 2047)
                return bSig != 0ul ? _PropagateNaN64(a, b) : _Pack64(sign ^ 1, 2047, 0ul);
            if (aExp == 0)
                diff += 1;
            else
                aSig = aSig | hidden;
            aSig = _ShiftRightJam64(aSig, -diff);
            bSig = bSig | hidden;
            return _NormalizeRoundPack64(sign ^ 1, bExp - 1, bSig - aSig);
        }
        if (aExp == 2047)
            return (aSig | bSig) != 0ul ? _PropagateNaN64(a, b) : _DefaultNaN;
        if (aExp == 0)
        {
            aExp = 1;
            bExp = 1;
        }
        if (bSig < aSig)
            return _NormalizeRoundPack64(sign, aExp - 1, aSig - bSig);
        if (aSig < bSig)
            return _NormalizeRoundPack64(sign ^ 1, bExp - 1, bSig - aSig);
        return 0ul; // x - x = +0
    }
}

extern "C" double __adddf3(double x, double y)
{
    uint64 a = _DoubleToBits(x);
    uint64 b = _DoubleToBits(y);
    int sign = _Sign64(a);
    return _BitsToDouble(sign == _Sign64(b) ? _AddSigs64(a, b, sign) : _SubSigs64(a, b, sign));
}

extern "C" double __subdf3(double x, double y)
{
    uint64 a = _DoubleToBits(x);
    uint64 b = _DoubleToBits(y);
    int sign = _Sign64(a);
    return _BitsToDouble(sign == _Sign64(b) ? _SubSigs64(a, b, sign) : _AddSigs64(a, b, sign));
}

// ---------------------------------------------------------------------------
// Multiplication and division
// ---------------------------------------------------------------------------

// The 128-bit product of two 64-bit numbers: high, and low through 'low'.
uint64 _Mul64To128(uint64 a, uint64 b, ref uint64 low)
{
    unchecked
    {
        uint64 aLow = a & 4294967295ul;
        uint64 aHigh = a >> 32;
        uint64 bLow = b & 4294967295ul;
        uint64 bHigh = b >> 32;
        uint64 ll = aLow * bLow;
        uint64 lh = aLow * bHigh;
        uint64 hl = aHigh * bLow;
        uint64 hh = aHigh * bHigh;
        uint64 mid = lh + hl;
        if (mid < lh)
            hh += 4294967296ul; // the carry of the middle: 2^96
        hh += mid >> 32;
        uint64 lo = ll + (mid << 32);
        if (lo < ll)
            hh += 1ul;
        low = lo;
        return hh;
    }
}

extern "C" double __muldf3(double x, double y)
{
    unchecked
    {
        uint64 a = _DoubleToBits(x);
        uint64 b = _DoubleToBits(y);
        int sign = _Sign64(a) ^ _Sign64(b);
        int aExp = _Exp64(a);
        int bExp = _Exp64(b);
        uint64 aSig = _Frac64(a);
        uint64 bSig = _Frac64(b);
        if (aExp == 2047)
        {
            if (aSig != 0ul || (bExp == 2047 && bSig != 0ul))
                return _BitsToDouble(_PropagateNaN64(a, b));
            if (bExp == 0 && bSig == 0ul)
                return _BitsToDouble(_DefaultNaN); // inf * 0
            return _BitsToDouble(_Pack64(sign, 2047, 0ul));
        }
        if (bExp == 2047)
        {
            if (bSig != 0ul)
                return _BitsToDouble(_PropagateNaN64(a, b));
            if (aExp == 0 && aSig == 0ul)
                return _BitsToDouble(_DefaultNaN);
            return _BitsToDouble(_Pack64(sign, 2047, 0ul));
        }
        if (aExp == 0)
        {
            if (aSig == 0ul)
                return _BitsToDouble(_Pack64(sign, 0, 0ul));
            aSig = _NormalizeSubnormal64(aSig, ref aExp);
        }
        if (bExp == 0)
        {
            if (bSig == 0ul)
                return _BitsToDouble(_Pack64(sign, 0, 0ul));
            bSig = _NormalizeSubnormal64(bSig, ref bExp);
        }
        int exp = aExp + bExp - 1023;
        aSig = (aSig | 4503599627370496ul) << 10; // the hidden bit, 2^52
        bSig = (bSig | 4503599627370496ul) << 11;
        uint64 low = 0ul;
        uint64 sig = _Mul64To128(aSig, bSig, ref low);
        if (low != 0ul)
            sig = sig | 1ul;
        if ((int64)(sig << 1) >= 0)
        {
            sig = sig << 1;
            exp -= 1;
        }
        return _BitsToDouble(_RoundPack64(sign, exp, sig));
    }
}

extern "C" double __divdf3(double x, double y)
{
    unchecked
    {
        uint64 a = _DoubleToBits(x);
        uint64 b = _DoubleToBits(y);
        int sign = _Sign64(a) ^ _Sign64(b);
        int aExp = _Exp64(a);
        int bExp = _Exp64(b);
        uint64 aSig = _Frac64(a);
        uint64 bSig = _Frac64(b);
        if (aExp == 2047)
        {
            if (aSig != 0ul)
                return _BitsToDouble(_PropagateNaN64(a, b));
            if (bExp == 2047)
                return _BitsToDouble(bSig != 0ul ? _PropagateNaN64(a, b) : _DefaultNaN); // inf / inf
            return _BitsToDouble(_Pack64(sign, 2047, 0ul));
        }
        if (bExp == 2047)
        {
            if (bSig != 0ul)
                return _BitsToDouble(_PropagateNaN64(a, b));
            return _BitsToDouble(_Pack64(sign, 0, 0ul));
        }
        if (bExp == 0)
        {
            if (bSig == 0ul)
            {
                if (aExp == 0 && aSig == 0ul)
                    return _BitsToDouble(_DefaultNaN); // 0 / 0
                return _BitsToDouble(_Pack64(sign, 2047, 0ul));
            }
            bSig = _NormalizeSubnormal64(bSig, ref bExp);
        }
        if (aExp == 0)
        {
            if (aSig == 0ul)
                return _BitsToDouble(_Pack64(sign, 0, 0ul));
            aSig = _NormalizeSubnormal64(aSig, ref aExp);
        }
        int exp = aExp - bExp + 1021;
        aSig = (aSig | 4503599627370496ul) << 10;
        bSig = (bSig | 4503599627370496ul) << 11;
        if (bSig <= aSig + aSig)
        {
            aSig = aSig >> 1;
            exp += 1;
        }
        // (aSig * 2^64) / bSig, one bit at a time; aSig < bSig
        uint64 q = 0ul;
        uint64 rem = aSig;
        for (var i = 0; i < 64; i += 1)
        {
            bool carry = (rem >> 63) != 0ul;
            rem = rem << 1;
            q = q << 1;
            if (carry || rem >= bSig)
            {
                rem = rem - bSig;
                q = q | 1ul;
            }
        }
        if (rem != 0ul)
            q = q | 1ul;
        return _BitsToDouble(_RoundPack64(sign, exp, q));
    }
}

extern "C" double __negdf2(double x)
{
    return _BitsToDouble(_DoubleToBits(x) ^ 9223372036854775808ul);
}

// ---------------------------------------------------------------------------
// Comparison: -1, 0, 1 (a < b, a == b, a > b), 2 if either is NaN (unordered)
// ---------------------------------------------------------------------------

extern "C" int __cs68k_fcmp_d(double x, double y)
{
    uint64 a = _DoubleToBits(x);
    uint64 b = _DoubleToBits(y);
    if (_IsNaN64(a) || _IsNaN64(b))
        return 2;
    uint64 magA = a & 9223372036854775807ul;
    uint64 magB = b & 9223372036854775807ul;
    if (magA == 0ul && magB == 0ul)
        return 0; // +0 == -0
    int aSign = _Sign64(a);
    int bSign = _Sign64(b);
    if (aSign != bSign)
        return aSign == 1 ? -1 : 1;
    if (a == b)
        return 0;
    bool less = magA < magB;
    if (aSign == 1)
        less = !less;
    return less ? -1 : 1;
}

extern "C" int __cs68k_fcmp_f(float x, float y)
{
    return __cs68k_fcmp_d(__extendsfdf2(x), __extendsfdf2(y));
}

// ---------------------------------------------------------------------------
// Conversions
// ---------------------------------------------------------------------------

extern "C" double __floatsidf(int value)
{
    unchecked
    {
        if (value == 0)
            return _BitsToDouble(0ul);
        int sign = value < 0 ? 1 : 0;
        uint64 abs = value < 0 ? (uint64)(-(int64)value) : (uint64)value;
        return _BitsToDouble(_NormalizeRoundPack64(sign, 1084, abs)); // 0x43C
    }
}

extern "C" double __floatunsidf(uint32 value)
{
    if (value == 0u)
        return _BitsToDouble(0ul);
    return _BitsToDouble(_NormalizeRoundPack64(0, 1084, (uint64)value));
}

extern "C" double __floatdidf(int64 value)
{
    unchecked
    {
        if (value == 0)
            return _BitsToDouble(0ul);
        if (value == -9223372036854775807 - 1)
            return _BitsToDouble(_Pack64(1, 1086, 0ul)); // -2^63
        int sign = value < 0 ? 1 : 0;
        uint64 abs = value < 0 ? (uint64)(-value) : (uint64)value;
        return _BitsToDouble(_NormalizeRoundPack64(sign, 1084, abs));
    }
}

extern "C" double __floatundidf(uint64 value)
{
    if (value == 0ul)
        return _BitsToDouble(0ul);
    if ((value >> 63) != 0ul)
        return _BitsToDouble(_NormalizeRoundPack64(0, 1085, _ShiftRightJam64(value, 1)));
    return _BitsToDouble(_NormalizeRoundPack64(0, 1084, value));
}

// The value truncated toward zero, clamped to [min, max] (NaN gives 0); as the magnitude and sign.
int64 _TruncClamp(double x, int64 min, uint64 max)
{
    unchecked
    {
        uint64 a = _DoubleToBits(x);
        if (_IsNaN64(a))
            return 0;
        int exp = _Exp64(a);
        int sign = _Sign64(a);
        if (exp < 1023)
            return 0; // |x| < 1
        uint64 mag;
        if (exp >= 1023 + 64)
            mag = 18446744073709551615ul; // at least 2^64: saturates below
        else
        {
            uint64 sig = _Frac64(a) | 4503599627370496ul;
            int shift = exp - 1075; // 1023 + 52
            if (shift >= 0)
                mag = shift >= 12 && sig >= (1ul << (64 - shift)) ? 18446744073709551615ul : sig << shift;
            else
                mag = sig >> (-shift);
        }
        if (sign == 1)
        {
            uint64 limit = (uint64)(-(min + 1)) + 1ul; // |min|, also for int64.MinValue
            if (min == 0 || mag == 0ul)
                return 0;
            if (mag >= limit)
                return min;
            return -(int64)mag;
        }
        if (mag >= max)
            return (int64)max;
        return (int64)mag;
    }
}

extern "C" int __fixdfsi(double x) { return (int)_TruncClamp(x, -2147483648, 2147483647ul); }
extern "C" uint32 __fixunsdfsi(double x) { return (uint32)_TruncClamp(x, 0, 4294967295ul); }
extern "C" int64 __fixdfdi(double x) { return _TruncClamp(x, -9223372036854775807 - 1, 9223372036854775807ul); }
extern "C" uint64 __fixunsdfdi(double x) { return unchecked((uint64)_TruncClamp(x, 0, 18446744073709551615ul)); }
extern "C" int __cs68k_dtoi_sat(double x) { return __fixdfsi(x); }
extern "C" uint32 __cs68k_dtou_sat(double x) { return __fixunsdfsi(x); }

// ---------------------------------------------------------------------------
// float
// ---------------------------------------------------------------------------

extern "C" double __extendsfdf2(float f)
{
    unchecked
    {
        uint32 a = _FloatToBits(f);
        int sign = (int)(a >> 31);
        int exp = (int)((a >> 23) & 255u);
        uint64 frac = (uint64)(a & 8388607u);
        if (exp == 255)
        {
            if (frac != 0ul)
                return _BitsToDouble(_Pack64(sign, 2047, (frac << 29) | 2251799813685248ul));
            return _BitsToDouble(_Pack64(sign, 2047, 0ul));
        }
        if (exp == 0)
        {
            if (frac == 0ul)
                return _BitsToDouble(_Pack64(sign, 0, 0ul));
            // subnormal float: normalize
            int shift = _LeadingZeros64(frac) - 40; // the leading bit to bit 23
            frac = (frac << shift) & 8388607ul;
            exp = 1 - shift;
        }
        return _BitsToDouble(_Pack64(sign, exp + 896, frac << 29)); // 1023 - 127
    }
}

// Rounds to float: the significand has its leading bit at bit 30, 7 bits below the result's lowest bit.
uint32 _RoundPack32(int sign, int exp, uint32 sig)
{
    unchecked
    {
        uint32 roundBits = sig & 127u;
        if (exp >= 253)
        {
            if (exp > 253 || (exp == 253 && (int)(sig + 64u) < 0))
                return ((uint32)sign << 31) + (255u << 23);
        }
        if (exp < 0)
        {
            int count = -exp;
            if (count >= 32)
                sig = sig != 0u ? 1u : 0u;
            else
            {
                uint32 lost = sig << (32 - count);
                sig = (sig >> count) | (lost != 0u ? 1u : 0u);
            }
            exp = 0;
            roundBits = sig & 127u;
        }
        sig = (sig + 64u) >> 7;
        if (roundBits == 64u)
            sig = sig & ~1u;
        if (sig == 0u)
            exp = 0;
        return ((uint32)sign << 31) + ((uint32)exp << 23) + sig;
    }
}

extern "C" float __truncdfsf2(double d)
{
    unchecked
    {
        uint64 a = _DoubleToBits(d);
        int sign = _Sign64(a);
        int exp = _Exp64(a);
        uint64 frac = _Frac64(a);
        if (exp == 2047)
        {
            if (frac != 0ul)
                return _BitsToFloat(((uint32)sign << 31) | 2143289344u | (uint32)(frac >> 29)); // quiet NaN
            return _BitsToFloat(((uint32)sign << 31) | 2139095040u);
        }
        uint32 sig = (uint32)_ShiftRightJam64(frac, 22);
        if (exp != 0 || sig != 0u)
        {
            sig = sig | 1073741824u; // 2^30
            exp -= 897; // 0x381
        }
        return _BitsToFloat(_RoundPack32(sign, exp, sig));
    }
}

extern "C" float __addsf3(float a, float b) { return __truncdfsf2(__adddf3(__extendsfdf2(a), __extendsfdf2(b))); }
extern "C" float __subsf3(float a, float b) { return __truncdfsf2(__subdf3(__extendsfdf2(a), __extendsfdf2(b))); }
extern "C" float __mulsf3(float a, float b) { return __truncdfsf2(__muldf3(__extendsfdf2(a), __extendsfdf2(b))); }
extern "C" float __divsf3(float a, float b) { return __truncdfsf2(__divdf3(__extendsfdf2(a), __extendsfdf2(b))); }
extern "C" float __floatsisf(int v) { return __truncdfsf2(__floatsidf(v)); }
extern "C" float __floatunsisf(uint32 v) { return __truncdfsf2(__floatunsidf(v)); }
extern "C" float __floatdisf(int64 v) { return __truncdfsf2(__floatdidf(v)); }
extern "C" float __floatundisf(uint64 v) { return __truncdfsf2(__floatundidf(v)); }
extern "C" int __fixsfsi(float f) { return __fixdfsi(__extendsfdf2(f)); }
extern "C" uint32 __fixunssfsi(float f) { return __fixunsdfsi(__extendsfdf2(f)); }
extern "C" int64 __fixsfdi(float f) { return __fixdfdi(__extendsfdf2(f)); }
extern "C" uint64 __fixunssfdi(float f) { return __fixunsdfdi(__extendsfdf2(f)); }
extern "C" int __cs68k_ftoi_sat(float f) { return __fixsfsi(f); }
extern "C" uint32 __cs68k_ftou_sat(float f) { return __fixunssfsi(f); }

// ---------------------------------------------------------------------------
// fmod (after musl): the remainder of x / y with the sign of x, exact
// ---------------------------------------------------------------------------

extern "C" double fmod(double x, double y)
{
    unchecked
    {
        uint64 ux = _DoubleToBits(x);
        uint64 uy = _DoubleToBits(y);
        int ex = _Exp64(ux);
        int ey = _Exp64(uy);
        int sx = _Sign64(ux);
        if ((uy << 1) == 0ul || _IsNaN64(uy) || ex == 2047)
            return __divdf3(__muldf3(x, y), __muldf3(x, y)); // NaN
        if ((ux << 1) <= (uy << 1))
        {
            if ((ux << 1) == (uy << 1))
                return __muldf3(0.0, x);
            return x;
        }
        uint64 i;
        if (ex == 0)
        {
            i = ux << 12;
            while ((int64)i >= 0)
            {
                ex -= 1;
                i = i << 1;
            }
            ux = ux << (-ex + 1);
        }
        else
        {
            ux = ux & _FracMask;
            ux = ux | 4503599627370496ul;
        }
        if (ey == 0)
        {
            i = uy << 12;
            while ((int64)i >= 0)
            {
                ey -= 1;
                i = i << 1;
            }
            uy = uy << (-ey + 1);
        }
        else
        {
            uy = uy & _FracMask;
            uy = uy | 4503599627370496ul;
        }
        for (; ex > ey; ex -= 1)
        {
            i = ux - uy;
            if ((i >> 63) == 0ul)
            {
                if (i == 0ul)
                    return __muldf3(0.0, x);
                ux = i;
            }
            ux = ux << 1;
        }
        i = ux - uy;
        if ((i >> 63) == 0ul)
        {
            if (i == 0ul)
                return __muldf3(0.0, x);
            ux = i;
        }
        while ((ux >> 52) == 0ul)
        {
            ux = ux << 1;
            ex -= 1;
        }
        if (ex > 0)
        {
            ux = ux - 4503599627370496ul;
            ux = ux | ((uint64)ex << 52);
        }
        else
            ux = ux >> (-ex + 1);
        ux = ux | ((uint64)sx << 63);
        return _BitsToDouble(ux);
    }
}

extern "C" float fmodf(float x, float y)
{
    return __truncdfsf2(fmod(__extendsfdf2(x), __extendsfdf2(y)));
}
