// The transcendental functions of the C library for the 68000 without an FPU: sin, cos, tan, asin, acos, atan,
// atan2, sinh, cosh, tanh, exp, expm1, log, log2, log10, pow, cbrt, hypot, scalbn. Ported from fdlibm (Sun
// Microsystems, "Developed at SunPro, a Sun Microsystems, Inc. business. Permission to use, copy, modify, and
// distribute this software is freely granted, provided that this notice is preserved.") in the form musl uses; the
// results are within one unit in the last place, like those of the usual C libraries.
//
// Part of the runtime of the m68k backend (added to the program only when that backend is used).

namespace System.M68k;

// ---------------------------------------------------------------------------
// The two 32-bit words of a double
// ---------------------------------------------------------------------------

uint32 _HighWord(double x) { unchecked { return (uint32)(_DoubleToBits(x) >> 32); } }
uint32 _LowWord(double x) { unchecked { return (uint32)_DoubleToBits(x); } }
double _FromWords(uint32 hi, uint32 lo) { unchecked { return _BitsToDouble(((uint64)hi << 32) | (uint64)lo); } }
double _ZeroLowWord(double x) { unchecked { return _BitsToDouble(_DoubleToBits(x) & 18446744069414584320ul); } }
double _WithHighWord(double x, uint32 hi) { return _FromWords(hi, _LowWord(x)); }

const double _Two1023 = 8.98846567431158e+307;
const double _Two54 = 1.8014398509481984e+16;
const double _Two24 = 16777216.0;
const double _TwoM24 = 5.960464477539063e-08;
const double _TwoM969 = 2.004168360008973e-292;

// x * 2^n
double _Scale2(double x, int n)
{
    double y = x;
    if (n > 1023)
    {
        y = y * _Two1023;
        n -= 1023;
        if (n > 1023)
        {
            y = y * _Two1023;
            n -= 1023;
            if (n > 1023)
                n = 1023;
        }
    }
    else if (n < -1022)
    {
        // the final n below -53 avoids rounding twice in the subnormal range
        y = y * _TwoM969;
        n += 1022 - 53;
        if (n < -1022)
        {
            y = y * _TwoM969;
            n += 1022 - 53;
            if (n < -1022)
                n = -1022;
        }
    }
    unchecked
    {
        return y * _BitsToDouble((uint64)(1023 + n) << 52);
    }
}

extern "C" double scalbn(double x, int n) { return _Scale2(x, n); }
extern "C" double ldexp(double x, int n) { return _Scale2(x, n); }

// ---------------------------------------------------------------------------
// sin, cos, tan: kernels on [-pi/4, pi/4] (x + y is the argument, y the tail)
// ---------------------------------------------------------------------------

double _KernelSin(double x, double y, int iy)
{
    const double _S1 = -1.66666666666666324348e-01;
    const double _S2 = 8.33333333332248946124e-03;
    const double _S3 = -1.98412698298579493134e-04;
    const double _S4 = 2.75573137070700676789e-06;
    const double _S5 = -2.50507602534068634195e-08;
    const double _S6 = 1.58969099521155010221e-10;
    double z = x * x;
    double v = z * x;
    double r = _S2 + z * (_S3 + z * (_S4 + z * (_S5 + z * _S6)));
    if (iy == 0)
        return x + v * (_S1 + z * r);
    return x - ((z * (0.5 * y - v * r) - y) - v * _S1);
}

double _KernelCos(double x, double y)
{
    const double _C1 = 4.16666666666666019037e-02;
    const double _C2 = -1.38888888888741095749e-03;
    const double _C3 = 2.48015872894767294178e-05;
    const double _C4 = -2.75573143513906633035e-07;
    const double _C5 = 2.08757232129817482790e-09;
    const double _C6 = -1.13596475577881948265e-11;
    double z = x * x;
    double w = z * z;
    double r = z * (_C1 + z * (_C2 + z * _C3)) + w * w * (_C4 + z * (_C5 + z * _C6));
    double hz = 0.5 * z;
    w = 1.0 - hz;
    return w + (((1.0 - w) - hz) + (z * r - x * y));
}

const ReadOnlySlice<double> _TanT = [
    3.33333333333334091986e-01, 1.33333333333201242699e-01, 5.39682539762260521377e-02, 2.18694882948595424599e-02,
    8.86323982359930005737e-03, 3.59207910759131235356e-03, 1.45620945432529025516e-03, 5.88041240820264096874e-04,
    2.46463134818469906812e-04, 7.81794442939557092300e-05, 7.14072491382608190305e-05, -1.85586374855275456654e-05,
    2.59073051863633712884e-05];

// tan(x + y), or -1/tan(x + y) when odd is 1
double _KernelTan(double x, double y, int odd)
{
    const double _Pio4 = 7.85398163397448278999e-01;
    const double _Pio4Lo = 3.06161699786838301793e-17;
    uint32 hx = _HighWord(x);
    bool big = (hx & 2147483647u) >= 1072010280u; // |x| >= 0.6744
    bool negative = false;
    if (big)
    {
        negative = (hx >> 31) != 0u;
        if (negative)
        {
            x = -x;
            y = -y;
        }
        x = (_Pio4 - x) + (_Pio4Lo - y);
        y = 0.0;
    }
    double z = x * x;
    double w = z * z;
    double r = _TanT[1] + w * (_TanT[3] + w * (_TanT[5] + w * (_TanT[7] + w * (_TanT[9] + w * _TanT[11]))));
    double v = z * (_TanT[2] + w * (_TanT[4] + w * (_TanT[6] + w * (_TanT[8] + w * (_TanT[10] + w * _TanT[12])))));
    double s = z * x;
    r = y + z * (s * (r + v) + y) + s * _TanT[0];
    w = x + r;
    if (big)
    {
        s = (double)(1 - 2 * odd);
        v = s - 2.0 * (x + (r - w * w / (w + s)));
        return negative ? -v : v;
    }
    if (odd == 0)
        return w;
    // -1.0/(x+r) has an error of up to 2 ulp: computed more precisely
    double w0 = _ZeroLowWord(w);
    v = r - (w0 - x); // w0 + v = r + x
    double a = -1.0 / w;
    double a0 = _ZeroLowWord(a);
    return a0 + a * (1.0 + a0 * w0 + a0 * v);
}

// ---------------------------------------------------------------------------
// Argument reduction: x - n*pi/2 = y0 + y1, the result is n
// ---------------------------------------------------------------------------

// 2/pi in 24-bit pieces (checked against a computation of pi with big integers)
const ReadOnlySlice<int> _IPio2 = [
    0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62, 0x95993C, 0x439041, 0xFE5163, 0xABDEBB, 0xC561B7,
    0x246E3A, 0x424DD2, 0xE00649, 0x2EEA09, 0xD1921C, 0xFE1DEB, 0x1CB129, 0xA73EE8, 0x8235F5, 0x2EBB44, 0x84E99C,
    0x7026B4, 0x5F7E41, 0x3991D6, 0x398353, 0x39F49C, 0x845F8B, 0xBDF928, 0x3B1FF8, 0x97FFDE, 0x05980F, 0xEF2F11,
    0x8B5A0A, 0x6D1F6D, 0x367ECF, 0x27CB09, 0xB74F46, 0x3F669E, 0x5FEA2D, 0x7527BA, 0xC7EBE5, 0xF17B3D, 0x0739F7,
    0x8A5292, 0xEA6BFB, 0x5FB11F, 0x8D5D08, 0x560330, 0x46FC7B, 0x6BABF0, 0xCFBC20, 0x9AF436, 0x1DA9E3, 0x91615E,
    0xE61B08, 0x659985, 0x5F14A0, 0x68408D, 0xFFD880, 0x4D7327, 0x310606, 0x1556CA, 0x73A8C9, 0x60E27B, 0xC08C6B];

// pi/2 in pieces of 24 bits
const ReadOnlySlice<double> _PIo2 = [
    1.57079625129699707031e+00, 7.54978941586159635335e-08, 5.39030252995776476554e-15, 3.28200341580791294123e-22,
    1.27065575308067607349e-29, 1.22933308981111328932e-36, 2.73370053816464559624e-44, 2.16741683877804819444e-51];

// The reduction of large arguments (fdlibm's __kernel_rem_pio2 for double precision): x[0..nx-1] are 24-bit pieces
// of the argument, scaled by 2^(-24*i + e0).
int _RemPio2Large(ref Fixed<double, 3> x, ref double y0, ref double y1, int e0, int nx)
{
    Fixed<int, 20> iq;
    Fixed<double, 20> f;
    Fixed<double, 20> fq;
    Fixed<double, 20> q;
    int jk = 4;
    int jp = jk;
    int jx = nx - 1;
    int jv = (e0 - 3) / 24;
    if (jv < 0)
        jv = 0;
    int q0 = e0 - 24 * (jv + 1);

    // f[0] to f[jx+jk] where f[jx+jk] = ipio2[jv+jk]
    int j = jv - jx;
    int m = jx + jk;
    for (var i = 0; i <= m; i += 1)
    {
        f[i] = j < 0 ? 0.0 : (double)_IPio2[j];
        j += 1;
    }
    for (var i = 0; i <= jk; i += 1)
    {
        double fw = 0.0;
        for (var k = 0; k <= jx; k += 1)
            fw = fw + x[k] * f[jx + i - k];
        q[i] = fw;
    }

    int jz = jk;
    int n = 0;
    int ih = 0;
    double z = 0.0;
    while (true)
    {
        // distill q[] into iq[] reversingly
        z = q[jz];
        int i = 0;
        for (var jj = jz; jj > 0; jj -= 1)
        {
            double fw = (double)(int)(_TwoM24 * z);
            iq[i] = (int)(z - _Two24 * fw);
            z = q[jj - 1] + fw;
            i += 1;
        }

        // n
        z = _Scale2(z, q0);
        z = z - 8.0 * _FloorDouble(z * 0.125); // the integer part below 8
        n = (int)z;
        z = z - (double)n;
        ih = 0;
        if (q0 > 0)
        {
            // iq[jz-1] is needed for n
            int bits = iq[jz - 1] >> (24 - q0);
            n += bits;
            iq[jz - 1] = iq[jz - 1] - (bits << (24 - q0));
            ih = iq[jz - 1] >> (23 - q0);
        }
        else if (q0 == 0)
            ih = iq[jz - 1] >> 23;
        else if (z >= 0.5)
            ih = 2;

        if (ih > 0)
        {
            // q > 0.5
            n += 1;
            int carry = 0;
            for (var k = 0; k < jz; k += 1)
            {
                // 1 - q
                int v = iq[k];
                if (carry == 0)
                {
                    if (v != 0)
                    {
                        carry = 1;
                        iq[k] = 16777216 - v;
                    }
                }
                else
                    iq[k] = 16777215 - v;
            }
            if (q0 == 1)
                iq[jz - 1] = iq[jz - 1] & 8388607;
            else if (q0 == 2)
                iq[jz - 1] = iq[jz - 1] & 4194303;
            if (ih == 2)
            {
                z = 1.0 - z;
                if (carry != 0)
                    z = z - _Scale2(1.0, q0);
            }
        }

        // recomputation needed?
        if (z == 0.0)
        {
            int any = 0;
            for (var k = jz - 1; k >= jk; k -= 1)
                any = any | iq[k];
            if (any == 0)
            {
                int more = 1;
                while (iq[jk - more] == 0)
                    more += 1;
                for (var k = jz + 1; k <= jz + more; k += 1)
                {
                    // add q[jz+1] to q[jz+more]
                    f[jx + k] = (double)_IPio2[jv + k];
                    double fw = 0.0;
                    for (var t = 0; t <= jx; t += 1)
                        fw = fw + x[t] * f[jx + k - t];
                    q[k] = fw;
                }
                jz += more;
                continue;
            }
        }
        break;
    }

    // chop off zero terms
    if (z == 0.0)
    {
        jz -= 1;
        q0 -= 24;
        while (iq[jz] == 0)
        {
            jz -= 1;
            q0 -= 24;
        }
    }
    else
    {
        // break z into 24 bits if necessary
        z = _Scale2(z, -q0);
        if (z >= _Two24)
        {
            double fw = (double)(int)(_TwoM24 * z);
            iq[jz] = (int)(z - _Two24 * fw);
            jz += 1;
            q0 += 24;
            iq[jz] = (int)fw;
        }
        else
            iq[jz] = (int)z;
    }

    // the integer chunks as floating point values
    double scale = _Scale2(1.0, q0);
    for (var i = jz; i >= 0; i -= 1)
    {
        q[i] = scale * (double)iq[i];
        scale = scale * _TwoM24;
    }

    // _PIo2[0..jp] * q[jz..0]
    for (var i = jz; i >= 0; i -= 1)
    {
        double fw = 0.0;
        for (var k = 0; k <= jp && k <= jz - i; k += 1)
            fw = fw + _PIo2[k] * q[i + k];
        fq[jz - i] = fw;
    }

    // compress fq[] into y0, y1
    double sum = 0.0;
    for (var i = jz; i >= 0; i -= 1)
        sum = sum + fq[i];
    y0 = ih == 0 ? sum : -sum;
    sum = fq[0] - sum;
    for (var i = 1; i <= jz; i += 1)
        sum = sum + fq[i];
    y1 = ih == 0 ? sum : -sum;
    return n & 7;
}

int _RemPio2(double x, ref double y0, ref double y1)
{
    const double _ToInt15 = 6755399441055744.0; // 1.5 * 2^52
    const double _Pio4 = 7.85398163397448278999e-01;
    const double _InvPio2 = 6.36619772367581382433e-01;
    const double _Pio2_1 = 1.57079632673412561417e+00;
    const double _Pio2_1t = 6.07710050650619224932e-11;
    const double _Pio2_2 = 6.07710050630396597660e-11;
    const double _Pio2_2t = 2.02226624879595063154e-21;
    const double _Pio2_3 = 2.02226624871116645580e-21;
    const double _Pio2_3t = 8.47842766036889956997e-32;

    uint32 hx = _HighWord(x);
    bool negative = (hx >> 31) != 0u;
    uint32 ix = hx & 2147483647u;
    if (ix < 1094263291u)
    {
        // |x| ~< 2^20*(pi/2): n = rint(x/(pi/2)), in up to three rounds of 33 bits of pi/2
        double fn = x * _InvPio2 + _ToInt15 - _ToInt15;
        int n = (int)fn;
        double r = x - fn * _Pio2_1;
        double w = fn * _Pio2_1t; // 1st round, good to 85 bits
        if (r - w < -_Pio4)
        {
            n -= 1;
            fn = fn - 1.0;
            r = x - fn * _Pio2_1;
            w = fn * _Pio2_1t;
        }
        else if (r - w > _Pio4)
        {
            n += 1;
            fn = fn + 1.0;
            r = x - fn * _Pio2_1;
            w = fn * _Pio2_1t;
        }
        y0 = r - w;
        int ey = _Exp64(_DoubleToBits(y0));
        int ex = (int)(ix >> 20);
        if (ex - ey > 16)
        {
            // 2nd round, good to 118 bits
            double t = r;
            w = fn * _Pio2_2;
            r = t - w;
            w = fn * _Pio2_2t - ((t - r) - w);
            y0 = r - w;
            ey = _Exp64(_DoubleToBits(y0));
            if (ex - ey > 49)
            {
                // 3rd round, good to 151 bits, covers all cases
                t = r;
                w = fn * _Pio2_3;
                r = t - w;
                w = fn * _Pio2_3t - ((t - r) - w);
                y0 = r - w;
            }
        }
        y1 = (r - y0) - w;
        return n;
    }
    if (ix >= 2146435072u)
    {
        // infinity or NaN
        y0 = x - x;
        y1 = y0;
        return 0;
    }
    // z = |x| scaled to [2^23, 2^24), in three pieces of 24 bits
    unchecked
    {
        double z = _BitsToDouble((_DoubleToBits(x) & _FracMask) | ((uint64)(1023 + 23) << 52));
        Fixed<double, 3> tx;
        int i = 0;
        while (i < 2)
        {
            tx[i] = (double)(int)z;
            z = (z - tx[i]) * _Two24;
            i += 1;
        }
        tx[2] = z;
        while (tx[i] == 0.0)
            i -= 1; // skip zero terms; the first one is not zero
        double t0 = 0.0;
        double t1 = 0.0;
        int n = _RemPio2Large(ref tx, ref t0, ref t1, (int)(ix >> 20) - (1023 + 23), i + 1);
        if (negative)
        {
            y0 = -t0;
            y1 = -t1;
            return -n;
        }
        y0 = t0;
        y1 = t1;
        return n;
    }
}

extern "C" double sin(double x)
{
    uint32 ix = _HighWord(x) & 2147483647u;
    if (ix <= 1072243195u)
    {
        // |x| ~< pi/4
        if (ix < 1045430272u)
            return x; // |x| < 2^-26
        return _KernelSin(x, 0.0, 0);
    }
    if (ix >= 2146435072u)
        return x - x; // infinity or NaN
    double y0 = 0.0;
    double y1 = 0.0;
    int n = _RemPio2(x, ref y0, ref y1);
    switch (n & 3)
    {
    case 0:
        return _KernelSin(y0, y1, 1);
    case 1:
        return _KernelCos(y0, y1);
    case 2:
        return -_KernelSin(y0, y1, 1);
    default:
        return -_KernelCos(y0, y1);
    }
}

extern "C" double cos(double x)
{
    uint32 ix = _HighWord(x) & 2147483647u;
    if (ix <= 1072243195u)
    {
        if (ix < 1044816030u)
            return 1.0; // |x| < 2^-27 * sqrt(2)
        return _KernelCos(x, 0.0);
    }
    if (ix >= 2146435072u)
        return x - x;
    double y0 = 0.0;
    double y1 = 0.0;
    int n = _RemPio2(x, ref y0, ref y1);
    switch (n & 3)
    {
    case 0:
        return _KernelCos(y0, y1);
    case 1:
        return -_KernelSin(y0, y1, 1);
    case 2:
        return -_KernelCos(y0, y1);
    default:
        return _KernelSin(y0, y1, 1);
    }
}

extern "C" double tan(double x)
{
    uint32 ix = _HighWord(x) & 2147483647u;
    if (ix <= 1072243195u)
    {
        if (ix < 1044381696u)
            return x; // |x| < 2^-27
        return _KernelTan(x, 0.0, 0);
    }
    if (ix >= 2146435072u)
        return x - x;
    double y0 = 0.0;
    double y1 = 0.0;
    int n = _RemPio2(x, ref y0, ref y1);
    return _KernelTan(y0, y1, n & 1);
}

// ---------------------------------------------------------------------------
// atan, atan2, asin, acos
// ---------------------------------------------------------------------------

const ReadOnlySlice<double> _ATanHi = [4.63647609000806093515e-01, 7.85398163397448278999e-01, 9.82793723247329054082e-01, 1.57079632679489655800e+00];
const ReadOnlySlice<double> _ATanLo = [2.26987774529616870924e-17, 3.06161699786838301793e-17, 1.39033110312309984516e-17, 6.12323399573676603587e-17];
const ReadOnlySlice<double> _ATanT = [
    3.33333333333329318027e-01, -1.99999999998764832476e-01, 1.42857142725034663711e-01, -1.11111104054623557880e-01,
    9.09088713343650656196e-02, -7.69187620504482999495e-02, 6.66107313738753120669e-02, -5.83357013379057348645e-02,
    4.97687799461593236017e-02, -3.65315727442169155270e-02, 1.62858201153657823623e-02];

double _ATanDouble(double x)
{
    uint32 hx = _HighWord(x);
    bool negative = (hx >> 31) != 0u;
    uint32 ix = hx & 2147483647u;
    int id;
    if (ix >= 1141899264u)
    {
        // |x| >= 2^66
        if (_IsNaN64(_DoubleToBits(x)))
            return x;
        return negative ? -_ATanHi[3] : _ATanHi[3];
    }
    if (ix < 1071382528u)
    {
        // |x| < 0.4375
        if (ix < 1044381696u)
            return x; // |x| < 2^-27
        id = -1;
    }
    else
    {
        x = _FabsDouble(x);
        if (ix < 1072889856u)
        {
            // |x| < 1.1875
            if (ix < 1072037888u)
            {
                // 7/16 <= |x| < 11/16
                id = 0;
                x = (2.0 * x - 1.0) / (2.0 + x);
            }
            else
            {
                // 11/16 <= |x| < 19/16
                id = 1;
                x = (x - 1.0) / (x + 1.0);
            }
        }
        else if (ix < 1073971200u)
        {
            // |x| < 2.4375
            id = 2;
            x = (x - 1.5) / (1.0 + 1.5 * x);
        }
        else
        {
            // 2.4375 <= |x| < 2^66
            id = 3;
            x = -1.0 / x;
        }
    }
    double z = x * x;
    double w = z * z;
    // the sum of _ATanT[i]*z^(i+1) as an odd and an even polynomial
    double s1 = z * (_ATanT[0] + w * (_ATanT[2] + w * (_ATanT[4] + w * (_ATanT[6] + w * (_ATanT[8] + w * _ATanT[10])))));
    double s2 = w * (_ATanT[1] + w * (_ATanT[3] + w * (_ATanT[5] + w * (_ATanT[7] + w * _ATanT[9]))));
    if (id < 0)
        return x - x * (s1 + s2);
    z = _ATanHi[id] - (x * (s1 + s2) - _ATanLo[id] - x);
    return negative ? -z : z;
}

extern "C" double atan(double x) { return _ATanDouble(x); }

extern "C" double atan2(double y, double x)
{
    const double _Pi = 3.1415926535897931160e+00;
    const double _PiLo = 1.2246467991473531772e-16;
    unchecked
    {
        if (_IsNaN64(_DoubleToBits(x)) || _IsNaN64(_DoubleToBits(y)))
            return x + y;
        uint32 ix = _HighWord(x);
        uint32 lx = _LowWord(x);
        uint32 iy = _HighWord(y);
        uint32 ly = _LowWord(y);
        if (((ix - 1072693248u) | lx) == 0u)
            return _ATanDouble(y); // x = 1.0
        uint32 m = ((iy >> 31) & 1u) | ((ix >> 30) & 2u); // 2*sign(x) + sign(y)
        ix = ix & 2147483647u;
        iy = iy & 2147483647u;

        if ((iy | ly) == 0u)
        {
            // y = 0
            if (m <= 1u)
                return y;
            return m == 2u ? _Pi : -_Pi;
        }
        if ((ix | lx) == 0u)
            return (m & 1u) != 0u ? -_Pi / 2.0 : _Pi / 2.0; // x = 0
        if (ix == 2146435072u)
        {
            // x is infinite
            if (iy == 2146435072u)
            {
                if (m == 0u)
                    return _Pi / 4.0;
                if (m == 1u)
                    return -_Pi / 4.0;
                if (m == 2u)
                    return 3.0 * _Pi / 4.0;
                return -3.0 * _Pi / 4.0;
            }
            if (m == 0u)
                return 0.0;
            if (m == 1u)
                return -0.0;
            if (m == 2u)
                return _Pi;
            return -_Pi;
        }
        // |y/x| > 2^64
        if (ix + (64u << 20) < iy || iy == 2146435072u)
            return (m & 1u) != 0u ? -_Pi / 2.0 : _Pi / 2.0;

        // z = atan(|y/x|) without spurious underflow
        double z;
        if ((m & 2u) != 0u && iy + (64u << 20) < ix)
            z = 0.0; // |y/x| < 2^-64, x < 0
        else
            z = _ATanDouble(_FabsDouble(y / x));
        if (m == 0u)
            return z;
        if (m == 1u)
            return -z;
        if (m == 2u)
            return _Pi - (z - _PiLo);
        return (z - _PiLo) - _Pi;
    }
}

const double _Pio2Hi = 1.57079632679489655800e+00;
const double _Pio2Lo = 6.12323399573676603587e-17;

double _ASinR(double z)
{
    const double _PS0 = 1.66666666666666657415e-01;
    const double _PS1 = -3.25565818622400915405e-01;
    const double _PS2 = 2.01212532134862925881e-01;
    const double _PS3 = -4.00555345006794114027e-02;
    const double _PS4 = 7.91534994289814532176e-04;
    const double _PS5 = 3.47933107596021167570e-05;
    const double _QS1 = -2.40339491173441421878e+00;
    const double _QS2 = 2.02094576023350569471e+00;
    const double _QS3 = -6.88283971605453293030e-01;
    const double _QS4 = 7.70381505559019352791e-02;
    double p = z * (_PS0 + z * (_PS1 + z * (_PS2 + z * (_PS3 + z * (_PS4 + z * _PS5)))));
    double q = 1.0 + z * (_QS1 + z * (_QS2 + z * (_QS3 + z * _QS4)));
    return p / q;
}

extern "C" double asin(double x)
{
    unchecked
    {
        uint32 hx = _HighWord(x);
        uint32 ix = hx & 2147483647u;
        if (ix >= 1072693248u)
        {
            // |x| >= 1 or NaN
            if (((ix - 1072693248u) | _LowWord(x)) == 0u)
                return x * _Pio2Hi; // asin(+-1) = +-pi/2
            return (x - x) / (x - x);
        }
        if (ix < 1071644672u)
        {
            // |x| < 0.5
            if (ix < 1045430272u && ix >= 1048576u)
                return x;
            return x + x * _ASinR(x * x);
        }
        // 1 > |x| >= 0.5
        double z = (1.0 - _FabsDouble(x)) * 0.5;
        double s = _SqrtDouble(z);
        double r = _ASinR(z);
        if (ix >= 1072640819u)
            x = _Pio2Hi - (2.0 * (s + s * r) - _Pio2Lo); // |x| > 0.975
        else
        {
            // f + c = sqrt(z)
            double f = _ZeroLowWord(s);
            double c = (z - f * f) / (s + f);
            x = 0.5 * _Pio2Hi - (2.0 * s * r - (_Pio2Lo - 2.0 * c) - (0.5 * _Pio2Hi - 2.0 * f));
        }
        return (hx >> 31) != 0u ? -x : x;
    }
}

extern "C" double acos(double x)
{
    unchecked
    {
        uint32 hx = _HighWord(x);
        uint32 ix = hx & 2147483647u;
        if (ix >= 1072693248u)
        {
            // |x| >= 1 or NaN
            if (((ix - 1072693248u) | _LowWord(x)) == 0u)
                return (hx >> 31) != 0u ? 2.0 * _Pio2Hi : 0.0; // acos(1) = 0, acos(-1) = pi
            return (x - x) / (x - x);
        }
        if (ix < 1071644672u)
        {
            // |x| < 0.5
            if (ix <= 1012924416u)
                return _Pio2Hi; // |x| < 2^-57
            return _Pio2Hi - (x - (_Pio2Lo - x * _ASinR(x * x)));
        }
        if ((hx >> 31) != 0u)
        {
            // x < -0.5
            double z = (1.0 + x) * 0.5;
            double s = _SqrtDouble(z);
            double w = _ASinR(z) * s - _Pio2Lo;
            return 2.0 * (_Pio2Hi - (s + w));
        }
        // x > 0.5
        double z = (1.0 - x) * 0.5;
        double s = _SqrtDouble(z);
        double df = _ZeroLowWord(s);
        double c = (z - df * df) / (s + df);
        double w = _ASinR(z) * s + c;
        return 2.0 * (df + w);
    }
}

// ---------------------------------------------------------------------------
// exp, expm1 and the hyperbolic functions
// ---------------------------------------------------------------------------

const double _Ln2Hi = 6.93147180369123816490e-01;
const double _Ln2Lo = 1.90821492927058770002e-10;
const double _InvLn2 = 1.44269504088896338700e+00;
const double _ExpP1 = 1.66666666666666019037e-01;
const double _ExpP2 = -2.77777777770155933842e-03;
const double _ExpP3 = 6.61375632143793436117e-05;
const double _ExpP4 = -1.65339022054652515390e-06;
const double _ExpP5 = 4.13813679705723846039e-08;

double _ExpDouble(double x)
{
    uint32 hx = _HighWord(x);
    bool negative = (hx >> 31) != 0u;
    hx = hx & 2147483647u;
    if (hx >= 1082535490u)
    {
        // |x| >= 708.39...
        if (_IsNaN64(_DoubleToBits(x)))
            return x;
        if (x > 709.782712893383973096)
            return x * _Two1023; // overflow (or infinity)
        if (x < -745.13321910194110842)
            return 0.0;
    }
    double hi;
    double lo;
    int k;
    if (hx > 1071001154u)
    {
        // |x| > 0.5 ln2
        if (hx >= 1072734898u)
            k = (int)(_InvLn2 * x + (negative ? -0.5 : 0.5)); // |x| >= 1.5 ln2
        else
            k = negative ? -1 : 1;
        hi = x - (double)k * _Ln2Hi; // exact here
        lo = (double)k * _Ln2Lo;
        x = hi - lo;
    }
    else if (hx > 1043333120u)
    {
        // |x| > 2^-28
        k = 0;
        hi = x;
        lo = 0.0;
    }
    else
        return 1.0 + x;
    double xx = x * x;
    double c = x - xx * (_ExpP1 + xx * (_ExpP2 + xx * (_ExpP3 + xx * (_ExpP4 + xx * _ExpP5))));
    double y = 1.0 + (x * c / (2.0 - c) - lo + hi);
    if (k == 0)
        return y;
    return _Scale2(y, k);
}

extern "C" double exp(double x) { return _ExpDouble(x); }

double _ExpM1Double(double x)
{
    const double _Q1 = -3.33333333333331316428e-02;
    const double _Q2 = 1.58730158725481460165e-03;
    const double _Q3 = -7.93650757867487942473e-05;
    const double _Q4 = 4.00821782732936239552e-06;
    const double _Q5 = -2.01099218183624371326e-07;
    uint32 hx = _HighWord(x);
    bool negative = (hx >> 31) != 0u;
    hx = hx & 2147483647u;
    if (hx >= 1078159482u)
    {
        // |x| >= 56 ln2
        if (_IsNaN64(_DoubleToBits(x)))
            return x;
        if (negative)
            return -1.0;
        if (x > 7.09782712893383973096e+02)
            return x * _Two1023;
    }
    int k;
    double c = 0.0;
    if (hx > 1071001154u)
    {
        // |x| > 0.5 ln2
        double hi;
        double lo;
        if (hx < 1072734898u)
        {
            // and |x| < 1.5 ln2
            if (!negative)
            {
                hi = x - _Ln2Hi;
                lo = _Ln2Lo;
                k = 1;
            }
            else
            {
                hi = x + _Ln2Hi;
                lo = -_Ln2Lo;
                k = -1;
            }
        }
        else
        {
            k = (int)(_InvLn2 * x + (negative ? -0.5 : 0.5));
            double t = (double)k;
            hi = x - t * _Ln2Hi; // exact here
            lo = t * _Ln2Lo;
        }
        x = hi - lo;
        c = (hi - x) - lo;
    }
    else if (hx < 1016070144u)
        return x; // |x| < 2^-54
    else
        k = 0;

    double hfx = 0.5 * x;
    double hxs = x * hfx;
    double r1 = 1.0 + hxs * (_Q1 + hxs * (_Q2 + hxs * (_Q3 + hxs * (_Q4 + hxs * _Q5))));
    double t3 = 3.0 - r1 * hfx;
    double e = hxs * ((r1 - t3) / (6.0 - x * t3));
    if (k == 0)
        return x - (x * e - hxs); // c is 0
    e = x * (e - c) - c;
    e = e - hxs;
    // exp(x) ~ 2^k (x reduced - e + 1)
    if (k == -1)
        return 0.5 * (x - e) - 0.5;
    if (k == 1)
    {
        if (x < -0.25)
            return -2.0 * (e - (x + 0.5));
        return 1.0 + 2.0 * (x - e);
    }
    unchecked
    {
        double twopk = _BitsToDouble((uint64)(1023 + k) << 52);
        if (k < 0 || k > 56)
        {
            // exp(x) - 1 is enough
            double y = x - e + 1.0;
            if (k == 1024)
                y = y * 2.0 * _Two1023;
            else
                y = y * twopk;
            return y - 1.0;
        }
        double twomk = _BitsToDouble((uint64)(1023 - k) << 52);
        if (k < 20)
            return (x - e + (1.0 - twomk)) * twopk;
        return (x - (e + twomk) + 1.0) * twopk;
    }
}

extern "C" double expm1(double x) { return _ExpM1Double(x); }

// exp(x) * sign for large x, without overflowing too early: exp(x - k ln2) * 2^(k-1) with k = 2043
double _ExpO2(double x, double sign)
{
    const double _KLn2 = 1416.0996898839683;
    double scale = _FromWords((uint32)(1023 + 2043 / 2) << 20, 0u);
    return _ExpDouble(x - _KLn2) * (sign * scale) * scale;
}

extern "C" double sinh(double x)
{
    unchecked
    {
        uint64 u = _DoubleToBits(x);
        double h = (u >> 63) != 0ul ? -0.5 : 0.5;
        u = u & 9223372036854775807ul;
        double absx = _BitsToDouble(u);
        uint32 w = (uint32)(u >> 32);
        if (w < 1082535490u)
        {
            // |x| < log(DBL_MAX)
            double t = _ExpM1Double(absx);
            if (w < 1072693248u)
            {
                if (w < 1072693248u - (26u << 20))
                    return x;
                return h * (2.0 * t - t * t / (t + 1.0));
            }
            return h * (t + t / (t + 1.0));
        }
        // |x| > log(DBL_MAX) or NaN
        return _ExpO2(absx, 2.0 * h);
    }
}

extern "C" double cosh(double x)
{
    unchecked
    {
        uint64 u = _DoubleToBits(x) & 9223372036854775807ul;
        x = _BitsToDouble(u);
        uint32 w = (uint32)(u >> 32);
        if (w < 1072049730u)
        {
            // |x| < log(2)
            if (w < 1072693248u - (26u << 20))
                return 1.0;
            double t = _ExpM1Double(x);
            return 1.0 + t * t / (2.0 * (1.0 + t));
        }
        if (w < 1082535490u)
        {
            // |x| < log(DBL_MAX)
            double t = _ExpDouble(x);
            return 0.5 * (t + 1.0 / t);
        }
        return _ExpO2(x, 1.0);
    }
}

extern "C" double tanh(double x)
{
    unchecked
    {
        uint64 u = _DoubleToBits(x);
        bool negative = (u >> 63) != 0ul;
        u = u & 9223372036854775807ul;
        x = _BitsToDouble(u);
        uint32 w = (uint32)(u >> 32);
        double t;
        if (w > 1071748074u)
        {
            // |x| > log(3)/2 ~= 0.5493 or NaN
            if (w > 1077149696u)
                t = 1.0 - 0.0 / x; // |x| > 20 or NaN
            else
            {
                t = _ExpM1Double(2.0 * x);
                t = 1.0 - 2.0 / (t + 2.0);
            }
        }
        else if (w > 1070618798u)
        {
            // |x| > log(5/3)/2 ~= 0.2554
            t = _ExpM1Double(2.0 * x);
            t = t / (t + 2.0);
        }
        else if (w >= 1048576u)
        {
            // |x| >= 2^-1022
            t = _ExpM1Double(-2.0 * x);
            t = -t / (t + 2.0);
        }
        else
            t = x; // subnormal
        return negative ? -t : t;
    }
}

// ---------------------------------------------------------------------------
// log, log2, log10
// ---------------------------------------------------------------------------

const double _Lg1 = 6.666666666666735130e-01;
const double _Lg2 = 3.999999999940941908e-01;
const double _Lg3 = 2.857142874366239149e-01;
const double _Lg4 = 2.222219843214978396e-01;
const double _Lg5 = 1.818357216161805012e-01;
const double _Lg6 = 1.531383769920937332e-01;
const double _Lg7 = 1.479819860511658591e-01;

// The common part: x = 2^k * (1 + f) with 1 + f in [sqrt(2)/2, sqrt(2)]. Returns false (and the result in special)
// for zero, negative numbers, infinity, NaN and 1.
bool _LogReduce(double x, ref int k, ref double f, ref double special)
{
    unchecked
    {
        uint64 u = _DoubleToBits(x);
        uint32 hx = (uint32)(u >> 32);
        k = 0;
        if (hx < 1048576u || (hx >> 31) != 0u)
        {
            if ((u << 1) == 0ul)
            {
                special = -1.0 / (x * x); // log(+-0) = -infinity
                return false;
            }
            if ((hx >> 31) != 0u)
            {
                special = (x - x) / 0.0; // log(negative) = NaN
                return false;
            }
            // subnormal: scaled up
            k -= 54;
            x = x * _Two54;
            u = _DoubleToBits(x);
            hx = (uint32)(u >> 32);
        }
        else if (hx >= 2146435072u)
        {
            special = x;
            return false;
        }
        else if (hx == 1072693248u && (u << 32) == 0ul)
        {
            special = 0.0;
            return false;
        }
        // reduce x into [sqrt(2)/2, sqrt(2)]
        hx = hx + (1072693248u - 1072079006u);
        k += (int)(hx >> 20) - 1023;
        hx = (hx & 1048575u) + 1072079006u;
        u = ((uint64)hx << 32) | (u & 4294967295ul);
        f = _BitsToDouble(u) - 1.0;
        return true;
    }
}

extern "C" double log(double x)
{
    int k = 0;
    double f = 0.0;
    double special = 0.0;
    if (!_LogReduce(x, ref k, ref f, ref special))
        return special;
    double hfsq = 0.5 * f * f;
    double s = f / (2.0 + f);
    double z = s * s;
    double w = z * z;
    double t1 = w * (_Lg2 + w * (_Lg4 + w * _Lg6));
    double t2 = z * (_Lg1 + w * (_Lg3 + w * (_Lg5 + w * _Lg7)));
    double r = t2 + t1;
    double dk = (double)k;
    return s * (hfsq + r) + dk * _Ln2Lo - hfsq + f + dk * _Ln2Hi;
}

// hi + lo = log(1 + f), hi with 32 bits
void _LogParts(double f, ref double hi, ref double lo)
{
    double hfsq = 0.5 * f * f;
    double s = f / (2.0 + f);
    double z = s * s;
    double w = z * z;
    double t1 = w * (_Lg2 + w * (_Lg4 + w * _Lg6));
    double t2 = z * (_Lg1 + w * (_Lg3 + w * (_Lg5 + w * _Lg7)));
    double r = t2 + t1;
    hi = _ZeroLowWord(f - hfsq);
    lo = f - hi - hfsq + s * (hfsq + r);
}

extern "C" double log10(double x)
{
    const double _IvLn10Hi = 4.34294481878168880939e-01;
    const double _IvLn10Lo = 2.50829467116452752298e-11;
    const double _Log10_2Hi = 3.01029995663611771306e-01;
    const double _Log10_2Lo = 3.69423907715893078616e-13;
    int k = 0;
    double f = 0.0;
    double special = 0.0;
    if (!_LogReduce(x, ref k, ref f, ref special))
        return special;
    double hi = 0.0;
    double lo = 0.0;
    _LogParts(f, ref hi, ref lo);
    // valHi + valLo ~ log10(1 + f) + k*log10(2)
    double valHi = hi * _IvLn10Hi;
    double dk = (double)k;
    double y = dk * _Log10_2Hi;
    double valLo = dk * _Log10_2Lo + (lo + hi) * _IvLn10Lo + lo * _IvLn10Hi;
    double w = y + valHi;
    valLo = valLo + ((y - w) + valHi);
    valHi = w;
    return valLo + valHi;
}

extern "C" double log2(double x)
{
    const double _IvLn2Hi = 1.44269504072144627571e+00;
    const double _IvLn2Lo = 1.67517131648865118353e-10;
    int k = 0;
    double f = 0.0;
    double special = 0.0;
    if (!_LogReduce(x, ref k, ref f, ref special))
        return special;
    double hi = 0.0;
    double lo = 0.0;
    _LogParts(f, ref hi, ref lo);
    double valHi = hi * _IvLn2Hi;
    double valLo = (lo + hi) * _IvLn2Lo + lo * _IvLn2Hi;
    double y = (double)k;
    double w = y + valHi;
    valLo = valLo + ((y - w) + valHi);
    valHi = w;
    return valLo + valHi;
}

// ---------------------------------------------------------------------------
// pow
// ---------------------------------------------------------------------------

extern "C" double pow(double x, double y)
{
    const double _Two53 = 9007199254740992.0;
    const double _Huge = 1.0e300;
    const double _Tiny = 1.0e-300;
    const double _L1 = 5.99999999999994648725e-01;
    const double _L2 = 4.28571428578550184252e-01;
    const double _L3 = 3.33333329818377432918e-01;
    const double _L4 = 2.72728123808534006489e-01;
    const double _L5 = 2.30660745775561754067e-01;
    const double _L6 = 2.06975017800338417784e-01;
    const double _Lg2Full = 6.93147180559945286227e-01;
    const double _Lg2H = 6.93147182464599609375e-01;
    const double _Lg2L = -1.90465429995776804525e-09;
    const double _Ovt = 8.0085662595372944372e-17;
    const double _Cp = 9.61796693925975554329e-01;
    const double _CpH = 9.61796700954437255859e-01;
    const double _CpL = -7.02846165095275826516e-09;
    const double _IvLn2 = 1.44269504088896338700e+00;
    const double _IvLn2H = 1.44269502162933349609e+00;
    const double _IvLn2L = 1.92596299112661746887e-08;
    const double _DpH1 = 5.84962487220764160156e-01;
    const double _DpL1 = 1.35003920212974897128e-08;

    unchecked
    {
        int hx = (int)_HighWord(x);
        uint32 lx = _LowWord(x);
        int hy = (int)_HighWord(y);
        uint32 ly = _LowWord(y);
        int ix = hx & 2147483647;
        int iy = hy & 2147483647;

        if (((uint32)iy | ly) == 0u)
            return 1.0; // x^0 = 1, even for NaN
        if (hx == 1072693248 && lx == 0u)
            return 1.0; // 1^y = 1, even for NaN
        if (ix > 2146435072 || (ix == 2146435072 && lx != 0u) || iy > 2146435072 || (iy == 2146435072 && ly != 0u))
            return x + y;

        // yIsInt: 0 = y is not an integer, 1 = an odd one, 2 = an even one (only needed for x < 0)
        int yIsInt = 0;
        if (hx < 0)
        {
            if (iy >= 1128267776)
                yIsInt = 2; // |y| >= 2^53: even
            else if (iy >= 1072693248)
            {
                int k = (iy >> 20) - 1023;
                if (k > 20)
                {
                    uint32 j = ly >> (52 - k);
                    if ((j << (52 - k)) == ly)
                        yIsInt = 2 - (int)(j & 1u);
                }
                else if (ly == 0u)
                {
                    int j = iy >> (20 - k);
                    if ((j << (20 - k)) == iy)
                        yIsInt = 2 - (j & 1);
                }
            }
        }

        // special values of y
        if (ly == 0u)
        {
            if (iy == 2146435072)
            {
                // y is +-infinity
                if (((uint32)(ix - 1072693248) | lx) == 0u)
                    return 1.0; // (-1)^+-inf
                if (ix >= 1072693248)
                    return hy >= 0 ? y : 0.0; // (|x| > 1)^+-inf = inf, 0
                return hy >= 0 ? 0.0 : -y; // (|x| < 1)^+-inf = 0, inf
            }
            if (iy == 1072693248)
                return hy >= 0 ? x : 1.0 / x; // y is +-1
            if (hy == 1073741824)
                return x * x; // y is 2
            if (hy == 1071644672 && hx >= 0)
                return _SqrtDouble(x); // y is 0.5, x >= +0
        }

        double ax = _FabsDouble(x);
        // special values of x
        if (lx == 0u && (ix == 2146435072 || ix == 0 || ix == 1072693248))
        {
            // x is +-0, +-inf, +-1
            double z = ax;
            if (hy < 0)
                z = 1.0 / z;
            if (hx < 0)
            {
                if (((ix - 1072693248) | yIsInt) == 0)
                    z = (z - z) / (z - z); // (-1)^non-int is NaN
                else if (yIsInt == 1)
                    z = -z; // (x<0)^odd = -(|x|^odd)
            }
            return z;
        }

        double s = 1.0; // the sign of the result
        if (hx < 0)
        {
            if (yIsInt == 0)
                return (x - x) / (x - x); // (x<0)^(non-int) is NaN
            if (yIsInt == 1)
                s = -1.0;
        }

        double t1;
        double t2;
        if (iy > 1105199104)
        {
            // |y| > 2^31
            if (iy > 1139802112)
            {
                // |y| > 2^64: overflow or underflow
                if (ix <= 1072693247)
                    return hy < 0 ? _Huge * _Huge : _Tiny * _Tiny;
                if (ix >= 1072693248)
                    return hy > 0 ? _Huge * _Huge : _Tiny * _Tiny;
            }
            // overflow or underflow if x is not close to one
            if (ix < 1072693247)
                return hy < 0 ? s * _Huge * _Huge : s * _Tiny * _Tiny;
            if (ix > 1072693248)
                return hy > 0 ? s * _Huge * _Huge : s * _Tiny * _Tiny;
            // |1-x| <= 2^-20: log(x) by x - x^2/2 + x^3/3 - x^4/4
            double t = ax - 1.0;
            double w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25));
            double u = _IvLn2H * t;
            double v = t * _IvLn2L - w * _IvLn2;
            t1 = _ZeroLowWord(u + v);
            t2 = v - (t1 - u);
        }
        else
        {
            int n = 0;
            if (ix < 1048576)
            {
                // subnormal x
                ax = ax * _Two53;
                n -= 53;
                ix = (int)_HighWord(ax);
            }
            n += (ix >> 20) - 1023;
            int j = ix & 1048575;
            ix = j | 1072693248; // normalized
            int k;
            if (j <= 235662)
                k = 0; // |x| < sqrt(3/2)
            else if (j < 767610)
                k = 1; // |x| < sqrt(3)
            else
            {
                k = 0;
                n += 1;
                ix -= 1048576;
            }
            ax = _WithHighWord(ax, (uint32)ix);
            double bp = k == 0 ? 1.0 : 1.5;
            double dpH = k == 0 ? 0.0 : _DpH1;
            double dpL = k == 0 ? 0.0 : _DpL1;

            // ss = sH + sL = (x-1)/(x+1) or (x-1.5)/(x+1.5)
            double u = ax - bp;
            double v = 1.0 / (ax + bp);
            double ss = u * v;
            double sH = _ZeroLowWord(ss);
            // tH = ax + bp, high part
            double tH = _FromWords((uint32)(((ix >> 1) | 536870912) + 524288 + (k << 18)), 0u);
            double tL = ax - (tH - bp);
            double sL = v * ((u - sH * tH) - sH * tL);
            // log(ax)
            double s2 = ss * ss;
            double r = s2 * s2 * (_L1 + s2 * (_L2 + s2 * (_L3 + s2 * (_L4 + s2 * (_L5 + s2 * _L6)))));
            r = r + sL * (sH + ss);
            s2 = sH * sH;
            tH = _ZeroLowWord(3.0 + s2 + r);
            tL = r - ((tH - 3.0) - s2);
            // u + v = ss*(1+...)
            u = sH * tH;
            v = sL * tH + tL * ss;
            // 2/(3log2)*(ss+...)
            double pH = _ZeroLowWord(u + v);
            double pL = v - (pH - u);
            double zH = _CpH * pH; // _CpH + _CpL = 2/(3*log2)
            double zL = _CpL * pH + pL * _Cp + dpL;
            // log2(ax) = (ss+..)*2/(3*log2) = n + dpH + zH + zL
            double t = (double)n;
            t1 = _ZeroLowWord(((zH + zL) + dpH) + t);
            t2 = zL - (((t1 - t) - dpH) - zH);
        }

        // y = y1 + y2; (y1 + y2)*(t1 + t2)
        double y1 = _ZeroLowWord(y);
        double pl = (y - y1) * t1 + y * t2;
        double ph = y1 * t1;
        double z2 = pl + ph;
        int jz = (int)_HighWord(z2);
        uint32 iz = _LowWord(z2);
        if (jz >= 1083179008)
        {
            // z >= 1024
            if (((uint32)(jz - 1083179008) | iz) != 0u)
                return s * _Huge * _Huge; // overflow
            if (pl + _Ovt > z2 - ph)
                return s * _Huge * _Huge;
        }
        else if ((jz & 2147483647) >= 1083231232)
        {
            // z <= -1075
            if (((uint32)jz - 3230714880u | iz) != 0u)
                return s * _Tiny * _Tiny; // underflow
            if (pl <= z2 - ph)
                return s * _Tiny * _Tiny;
        }

        // 2^(ph + pl)
        int i = jz & 2147483647;
        int kk = (i >> 20) - 1023;
        int nn = 0;
        if (i > 1071644672)
        {
            // |z| > 0.5: nn = [z + 0.5]
            nn = jz + (1048576 >> (kk + 1));
            kk = ((nn & 2147483647) >> 20) - 1023; // the new k for nn
            double t = _FromWords((uint32)(nn & ~(1048575 >> kk)), 0u);
            nn = ((nn & 1048575) | 1048576) >> (20 - kk);
            if (jz < 0)
                nn = -nn;
            ph = ph - t;
        }
        double t = _ZeroLowWord(pl + ph);
        double u = t * _Lg2H;
        double v = (pl - (t - ph)) * _Lg2Full + t * _Lg2L;
        double z = u + v;
        double w = v - (z - u);
        t = z * z;
        double tt1 = z - t * (_ExpP1 + t * (_ExpP2 + t * (_ExpP3 + t * (_ExpP4 + t * _ExpP5))));
        double r = (z * tt1) / (tt1 - 2.0) - (w + z * w);
        z = 1.0 - (r - z);
        int jj = (int)_HighWord(z);
        jj += nn << 20;
        if ((jj >> 20) <= 0)
            z = _Scale2(z, nn); // subnormal result
        else
            z = _WithHighWord(z, (uint32)jj);
        return s * z;
    }
}

// ---------------------------------------------------------------------------
// cbrt, hypot
// ---------------------------------------------------------------------------

extern "C" double cbrt(double x)
{
    const uint32 _B1 = 715094163u; // (1023 - 1023/3 - 0.03306235651) * 2^20
    const uint32 _B2 = 696219795u; // (1023 - 1023/3 - 54/3 - 0.03306235651) * 2^20
    const double _P0 = 1.87595182427177009643;
    const double _P1 = -1.88497979543377169875;
    const double _P2 = 1.621429720105354466140;
    const double _P3 = -0.758397934778766047437;
    const double _P4 = 0.145996192886612446982;
    unchecked
    {
        uint64 u = _DoubleToBits(x);
        uint32 hx = (uint32)(u >> 32) & 2147483647u;
        if (hx >= 2146435072u)
            return x + x; // NaN, infinity
        if (hx < 1048576u)
        {
            // zero or subnormal
            u = _DoubleToBits(x * _Two54);
            hx = (uint32)(u >> 32) & 2147483647u;
            if (hx == 0u)
                return x;
            hx = hx / 3u + _B2;
        }
        else
            hx = hx / 3u + _B1;
        u = u & 9223372036854775808ul;
        u = u | ((uint64)hx << 32);
        double t = _BitsToDouble(u);

        // t to 23 bits with a polynomial
        double r = (t * t) * (t / x);
        t = t * ((_P0 + r * (_P1 + r * _P2)) + ((r * r) * r) * (_P3 + r * _P4));

        // rounded away from zero to 23 bits
        t = _BitsToDouble((_DoubleToBits(t) + 2147483648ul) & 18446744072635809792ul);

        // one Newton step to 53 bits
        double s = t * t; // exact
        r = x / s;
        double w = t + t; // exact
        r = (r - t) / (w + r);
        return t + t * r;
    }
}

// hi + lo = x*x exactly
void _Square(double x, ref double hi, ref double lo)
{
    const double _Split = 134217729.0; // 2^27 + 1
    double xc = x * _Split;
    double xh = x - xc + xc;
    double xl = x - xh;
    hi = x * x;
    lo = xh * xh - hi + 2.0 * xh * xl + xl * xl;
}

extern "C" double hypot(double x, double y)
{
    const double _Two700 = 5.260135901548374e+210;
    const double _TwoM700 = 1.90109156629516e-211;
    unchecked
    {
        uint64 ux = _DoubleToBits(x) & 9223372036854775807ul;
        uint64 uy = _DoubleToBits(y) & 9223372036854775807ul;
        if (ux < uy)
        {
            uint64 t = ux;
            ux = uy;
            uy = t;
        }
        int ex = (int)(ux >> 52);
        int ey = (int)(uy >> 52);
        x = _BitsToDouble(ux);
        y = _BitsToDouble(uy);
        if (ey == 2047)
            return y; // hypot(inf, nan) == inf
        if (ex == 2047 || uy == 0ul)
            return x;
        if (ex - ey > 64)
            return x + y;
        double z = 1.0;
        if (ex > 1023 + 510)
        {
            z = _Two700;
            x = x * _TwoM700;
            y = y * _TwoM700;
        }
        else if (ey < 1023 - 450)
        {
            z = _TwoM700;
            x = x * _Two700;
            y = y * _Two700;
        }
        double hx = 0.0;
        double lx = 0.0;
        double hy = 0.0;
        double ly = 0.0;
        _Square(x, ref hx, ref lx);
        _Square(y, ref hy, ref ly);
        return z * _SqrtDouble(ly + lx + hy + hx);
    }
}
