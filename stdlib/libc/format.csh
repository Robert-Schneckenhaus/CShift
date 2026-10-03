// The parts of a C library that the backends with their own C library share (AmigaOS: stdlib/amiga, WebAssembly:
// stdlib/wasm): the formatting of printf. The platform writes the text: __cs_libc_write(file, data, length), where a
// file null is stdout. The arguments are packed like on the stack of the 68000: 4 bytes for an int, a pointer or a
// char, 8 for a long long or a double, without gaps.

namespace System.LibC;

using System.M68k;

extern "C" void* malloc(nuint size);
extern "C" void free(void* memory);
extern "C" void __cs_libc_write(void* file, void* data, int length);

// ---------------------------------------------------------------------------
// printf, fprintf, snprintf: %d %i %u %x %X %c %s %p %% %e %f %g with flags (- 0 + space #), width, precision
// (also *), and the lengths l, ll, h, z. Called by the entries of the platform (AmigaRuntime.csh, stdlib/wasm).
// ---------------------------------------------------------------------------

// Where the text goes: kind 0 stdout, 1 a FILE, 2 a buffer of 'size' bytes.
struct _Sink
{
    int Kind;
    void* Target;
    int Size;
    int Count;       // the characters written (or that would have been)
    uint8* Chunk;    // the output of files is collected and written in pieces
    int ChunkLength;
}

void _Put(ref _Sink s, int c)
{
    unsafe
    {
        if (s.Kind == 2)
        {
            if (s.Count < s.Size - 1)
                ((uint8*)s.Target)[s.Count] = (uint8)c;
        }
        else
        {
            s.Chunk[s.ChunkLength] = (uint8)c;
            s.ChunkLength += 1;
            if (s.ChunkLength == 256)
                _Flush(ref s);
        }
        s.Count += 1;
    }
}

void _Flush(ref _Sink s)
{
    unsafe
    {
        if (s.Kind != 2 && s.ChunkLength > 0)
        {
            __cs_libc_write(s.Kind == 0 ? null : s.Target, s.Chunk, s.ChunkLength);
            s.ChunkLength = 0;
        }
    }
}

void _PutText(ref _Sink s, uint8* text, int length, int width, bool left)
{
    unsafe
    {
        for (var i = length; i < width && !left; i += 1)
            _Put(ref s, ' ');
        for (var i = 0; i < length; i += 1)
            _Put(ref s, text[i]);
        for (var i = length; i < width && left; i += 1)
            _Put(ref s, ' ');
    }
}

// sign, prefix and digits with the padding of the flags
void _PutNumber(ref _Sink s, string sign, string digits, int width, bool left, bool zero)
{
    int length = sign.Length + digits.Length;
    if (!left && !zero)
    {
        for (var i = length; i < width; i += 1)
            _Put(ref s, ' ');
    }
    foreach (var c in sign)
        _Put(ref s, (int)c);
    if (!left && zero)
    {
        for (var i = length; i < width; i += 1)
            _Put(ref s, '0');
    }
    foreach (var c in digits)
        _Put(ref s, (int)c);
    if (left)
    {
        for (var i = length; i < width; i += 1)
            _Put(ref s, ' ');
    }
}

string _Unsigned(uint64 value, int radix, bool upper)
{
    if (value == 0ul)
        return "0";
    string letters = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    var sb = StringBuilder.Create();
    var digits = List<char>.Create();
    while (value != 0ul)
    {
        digits.Add(letters[(int)(value % (uint64)radix)]);
        value = value / (uint64)radix;
    }
    for (var i = digits.Count() - 1; i >= 0; i -= 1)
        sb.Append(digits.Get(i));
    return sb.ToString();
}

extern "C" int __cs_vformat(int kind, void* target, int size, char* format, void* args)
{
    unsafe
    {
        uint8 chunk0 = 0;
        var s = _Sink { Kind = kind, Target = target, Size = size, Count = 0, Chunk = null, ChunkLength = 0 };
        if (kind != 2)
            s.Chunk = (uint8*)malloc((nuint)256);
        uint8* a = (uint8*)args;
        int i = 0;
        while (format[i] != 0)
        {
            char c = format[i];
            i += 1;
            if (c != '%')
            {
                _Put(ref s, (int)c);
                continue;
            }
            bool left = false;
            bool zero = false;
            bool plus = false;
            bool space = false;
            bool alt = false;
            while (true)
            {
                char f = format[i];
                if (f == '-')
                    left = true;
                else if (f == '0')
                    zero = true;
                else if (f == '+')
                    plus = true;
                else if (f == ' ')
                    space = true;
                else if (f == '#')
                    alt = true;
                else
                    break;
                i += 1;
            }
            int width = 0;
            if (format[i] == '*')
            {
                width = *(int*)a;
                a += 4;
                i += 1;
                if (width < 0)
                {
                    left = true;
                    width = -width;
                }
            }
            while (format[i] >= '0' && format[i] <= '9')
            {
                width = width * 10 + ((int)format[i] - 48);
                i += 1;
            }
            int precision = -1;
            if (format[i] == '.')
            {
                i += 1;
                precision = 0;
                if (format[i] == '*')
                {
                    precision = *(int*)a;
                    a += 4;
                    i += 1;
                }
                while (format[i] >= '0' && format[i] <= '9')
                {
                    precision = precision * 10 + ((int)format[i] - 48);
                    i += 1;
                }
            }
            int longs = 0;
            while (format[i] == 'l' || format[i] == 'h' || format[i] == 'z')
            {
                if (format[i] == 'l')
                    longs += 1;
                i += 1;
            }
            char conv = format[i];
            if (conv == 0)
                break;
            i += 1;
            switch (conv)
            {
            case 'd':
            case 'i':
            {
                int64 v;
                if (longs >= 2)
                {
                    v = *(int64*)a;
                    a += 8;
                }
                else
                {
                    v = (int64)*(int*)a;
                    a += 4;
                }
                string sign = v < 0 ? "-" : (plus ? "+" : (space ? " " : ""));
                uint64 mag = v < 0 ? unchecked((uint64)(-(v + 1)) + 1ul) : (uint64)v;
                string digits = _Unsigned(mag, 10, false);
                if (precision >= 0)
                    digits = digits.PadLeft(precision, '0');
                _PutNumber(ref s, sign, digits, width, left, zero && precision < 0);
                break;
            }
            case 'u':
            case 'x':
            case 'X':
            case 'p':
            {
                uint64 v;
                if (longs >= 2)
                {
                    v = *(uint64*)a;
                    a += 8;
                }
                else
                {
                    v = (uint64)*(uint32*)a;
                    a += 4;
                }
                string digits = _Unsigned(v, conv == 'u' ? 10 : 16, conv == 'X');
                if (precision >= 0)
                    digits = digits.PadLeft(precision, '0');
                string prefix = (conv == 'p' || (alt && v != 0ul && conv != 'u')) ? (conv == 'X' ? "0X" : "0x") : "";
                _PutNumber(ref s, prefix, digits, width, left, zero && precision < 0);
                break;
            }
            case 'c':
            {
                uint8 ch = (uint8)*(int*)a;
                a += 4;
                _PutText(ref s, &ch, 1, width, left);
                break;
            }
            case 's':
            {
                uint8* text = *(uint8**)a;
                a += 4;
                if (text == null)
                    text = (uint8*)"(null)".CStr();
                int n = 0;
                while (text[n] != 0 && (precision < 0 || n < precision))
                    n += 1;
                _PutText(ref s, text, n, width, left);
                break;
            }
            case 'e':
            case 'E':
            case 'f':
            case 'F':
            case 'g':
            case 'G':
            {
                double d = *(double*)a;
                a += 8;
                string sign = "";
                string body = _FormatDouble(d, conv, precision < 0 ? 6 : precision, alt, ref sign);
                if (sign.Length == 0)
                    sign = plus ? "+" : (space ? " " : "");
                bool finite = body[0] >= '0' && body[0] <= '9';
                _PutNumber(ref s, sign, body, width, left, zero && finite);
                break;
            }
            case '%':
                _Put(ref s, '%');
                break;
            default:
                _Put(ref s, '%');
                _Put(ref s, (int)conv);
                break;
            }
        }
        if (kind == 2 && size > 0)
            ((uint8*)target)[s.Count < size ? s.Count : size - 1] = 0;
        _Flush(ref s);
        if (s.Chunk != null)
            free(s.Chunk);
        return s.Count;
    }
}

// ---------------------------------------------------------------------------
// Doubles to text, exactly (like glibc: from the exact binary value, rounded half to even)
// ---------------------------------------------------------------------------

// big / divisor (in place), the remainder
uint32 _BigDivSmall(List<uint32> big, uint32 divisor)
{
    unchecked
    {
        uint64 rest = 0ul;
        for (var i = big.Count() - 1; i >= 0; i -= 1)
        {
            uint64 cur = (rest << 32) | (uint64)big.Get(i);
            big.Set(i, (uint32)(cur / (uint64)divisor));
            rest = cur % (uint64)divisor;
        }
        while (big.Count() > 0 && big.Get(big.Count() - 1) == 0u)
            big.RemoveAt(big.Count() - 1);
        return (uint32)rest;
    }
}

// All decimal digits of the exact value of a finite, positive double, and where the point is: value = 0.DIGITS * 10^point.
string _ExactDigits(uint64 bits, ref int point)
{
    unchecked
    {
        int e = (int)((bits >> 52) & 2047ul);
        uint64 m = bits & 4503599627370495ul;
        if (e == 0)
            e = 1;
        else
            m = m | 4503599627370496ul;
        e -= 1075; // value = m * 2^e
        var big = _BigOf((uint32)(m >> 32));
        big = _BigShiftLeft(big, 32);
        if (big.Count() == 0)
            big = _BigOf((uint32)m);
        else
            big.Set(0, (uint32)m);
        int decimals = 0;
        if (e >= 0)
            big = _BigShiftLeft(big, e);
        else
        {
            // m / 2^k = m * 5^k / 10^k
            for (var k = 0; k < -e; k += 1)
                _BigMulAdd(big, 5u, 0u);
            decimals = -e;
        }
        // the digits, lowest first, in groups of 9
        var groups = List<uint32>.Create();
        while (big.Count() > 0)
            groups.Add(_BigDivSmall(big, 1000000000u));
        var sb = StringBuilder.Create();
        for (var g = groups.Count() - 1; g >= 0; g -= 1)
        {
            string part = groups.Get(g).ToString();
            if (g != groups.Count() - 1)
                part = part.PadLeft(9, '0');
            sb.Append(part);
        }
        string digits = sb.ToString();
        if (digits.Length == 0)
            digits = "0";
        point = digits.Length - decimals;
        // without leading zeros
        int lead = 0;
        while (lead < digits.Length - 1 && digits[lead] == '0')
            lead += 1;
        point -= lead;
        return digits.Substring(lead).ToString();
    }
}

// the first 'count' digits, rounded half to even (the digits after them are exact); point moves on a carry
string _RoundDigits(string digits, int count, ref int point)
{
    if (count >= digits.Length)
        return digits.PadRight(count, '0');
    if (count < 0)
        return "";
    bool up;
    char next = digits[count];
    if (next > '5')
        up = true;
    else if (next < '5')
        up = false;
    else
    {
        bool rest = false;
        for (var i = count + 1; i < digits.Length; i += 1)
        {
            if (digits[i] != '0')
            {
                rest = true;
                break;
            }
        }
        up = rest || (count > 0 && ((int)digits[count - 1] - 48) % 2 == 1);
    }
    var chars = List<char>.Create();
    for (var i = 0; i < count; i += 1)
        chars.Add(digits[i]);
    if (up)
    {
        int k = count - 1;
        while (k >= 0 && chars.Get(k) == '9')
        {
            chars.Set(k, '0');
            k -= 1;
        }
        if (k >= 0)
            chars.Set(k, (char)((int)chars.Get(k) + 1));
        else
        {
            chars.Insert(0, '1');
            point += 1;
            if (count > 0)
                chars.RemoveAt(chars.Count() - 1);
            else
                return "1";
        }
    }
    var sb = StringBuilder.Create();
    foreach (var ch in chars.ToArray())
        sb.Append(ch);
    return sb.ToString();
}

string _Exponent(int x)
{
    string digits = (x < 0 ? -x : x).ToString().PadLeft(2, '0');
    return (x < 0 ? "-" : "+") + digits;
}

// the text of %e, %f or %g (without the sign, which goes to 'sign' for negative numbers)
string _FormatDouble(double d, char conv, int precision, bool alt, ref string sign)
{
    unchecked
    {
        uint64 bits = _DoubleToBits(d);
        if ((bits >> 63) != 0ul)
            sign = "-";
        bits = bits & 9223372036854775807ul;
        bool upper = conv == 'E' || conv == 'F' || conv == 'G';
        if ((bits >> 52) == 2047ul)
        {
            string special = (bits & 4503599627370495ul) != 0ul ? "nan" : "inf";
            return upper ? special.ToUpper() : special;
        }
        char lower = upper ? (char)((int)conv + 32) : conv;
        int point = 1;
        string digits = bits == 0ul ? "0" : _ExactDigits(bits, ref point);
        if (bits == 0ul)
            point = 1;
        if (lower == 'g')
        {
            int p = precision == 0 ? 1 : precision;
            int pt = point;
            string r = _RoundDigits(digits, p, ref pt);
            int x = pt - 1; // the exponent of the rounded value
            if (bits == 0ul)
                x = 0;
            string text;
            if (x < -4 || x >= p)
            {
                string mantissa = r.Substring(0, 1).ToString();
                string fraction = r.Substring(1).ToString();
                if (!alt)
                    fraction = fraction.TrimEnd('0').ToString();
                text = mantissa + (fraction.Length > 0 || alt ? "." + fraction : "") + (upper ? "E" : "e") + _Exponent(x);
            }
            else
            {
                text = _Fixed(r, pt, p - 1 - x);
                if (!alt && text.Contains("."))
                {
                    text = text.TrimEnd('0').ToString();
                    if (text.EndsWith("."))
                        text = text.Substring(0, text.Length - 1).ToString();
                }
            }
            return text;
        }
        if (lower == 'e')
        {
            int pt = point;
            string r = _RoundDigits(digits, precision + 1, ref pt);
            int x = bits == 0ul ? 0 : pt - 1;
            string fraction = r.Substring(1).ToString();
            return r.Substring(0, 1) + (precision > 0 || alt ? "." + fraction : "") + (upper ? "E" : "e") + _Exponent(x);
        }
        // %f: 'precision' digits after the point
        int pf = point;
        int count = point + precision;
        string rf;
        if (count < 0)
        {
            rf = "";
            pf = point;
        }
        else
            rf = _RoundDigits(digits, count, ref pf);
        if (rf.Length == 0 || (count <= 0 && rf != "1"))
        {
            // the value rounds to zero (or to one unit in the last place)
            if (count == 0 && rf == "1")
                return _Fixed("1", pf, precision);
            return _Fixed("0", 1, precision);
        }
        string fixedText = _Fixed(rf, pf, precision);
        if (alt && precision == 0)
            fixedText += ".";
        return fixedText;
    }
}

// digits (0.DIGITS * 10^point) with 'decimals' digits after the point
string _Fixed(string digits, int point, int decimals)
{
    var sb = StringBuilder.Create();
    if (point <= 0)
        sb.Append('0');
    else
    {
        for (var i = 0; i < point; i += 1)
            sb.Append(i < digits.Length ? digits[i] : '0');
    }
    if (decimals > 0)
    {
        sb.Append('.');
        for (var i = 0; i < decimals; i += 1)
        {
            int at = point + i;
            sb.Append(at >= 0 && at < digits.Length ? digits[at] : '0');
        }
    }
    return sb.ToString();
}
