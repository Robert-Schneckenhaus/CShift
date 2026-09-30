// The C library of CShift programs on AmigaOS (added to the program only for an amigaos target): the functions the
// generated code and the standard library use (malloc/free, printf, files, directories, getenv, ...), written on
// exec.library and dos.library. It runs on every AmigaOS from 1.3 on; functions that need a newer dos.library
// (getenv, getcwd, system with a result) check its version. The startup code, exit, printf's entries, memcpy & co and
// the stubs that call the libraries (__exec_*, __dos_*) are in selfhost/src/M68k/AmigaRuntime.csh.

namespace System.Amiga;

using System.M68k;

extern "C" int __exec_AllocMem(int size, int requirements);
extern "C" void __exec_FreeMem(void* memory, int size);
extern "C" void* __exec_FindTask(void* name);
extern "C" void* __exec_OpenLibrary(char* name, int version);
extern "C" void __exec_CloseLibrary(void* library);
extern "C" int __dos_Open(char* name, int mode);
extern "C" int __dos_Close(int file);
extern "C" int __dos_Read(int file, void* buffer, int length);
extern "C" int __dos_Write(int file, void* buffer, int length);
extern "C" int __dos_Input();
extern "C" int __dos_Output();
extern "C" int __dos_Seek(int file, int position, int mode);
extern "C" int __dos_DeleteFile(char* name);
extern "C" int __dos_Lock(char* name, int mode);
extern "C" void __dos_UnLock(int lock);
extern "C" int __dos_Examine(int lock, void* info);
extern "C" int __dos_ExNext(int lock, void* info);
extern "C" int __dos_CreateDir(char* name);
extern "C" int __dos_CurrentDir(int lock);
extern "C" void __dos_Delay(int ticks);
extern "C" int __dos_Execute(char* command, int input, int output);
extern "C" int __dos_NameFromLock(int lock, char* buffer, int length);
extern "C" int __dos_SystemTagList(char* command, void* tags);
extern "C" int __dos_GetVar(char* name, char* buffer, int size, int flags);
extern "C" void* __dos_DateStamp(void* stamp);
extern "C" int __cs_amiga_get(int index);
extern "C" void __cs_amiga_set(int index, int value);
extern "C" int main(int argc, char** argv);

// the slots of __cs_amiga_get/__cs_amiga_set (AmigaRuntime.csh)
const int _VarSysBase = 0;
const int _VarDOSBase = 1;
const int _VarThisTask = 2;
const int _VarArgPtr = 4;
const int _VarArgLen = 5;
const int _VarStdout = 8;
const int _VarStderr = 9;

const int _MemClear = 65536;       // MEMF_CLEAR
const int _ModeOldFile = 1005;
const int _ModeNewFile = 1006;
const int _ModeReadWrite = 1004;
const int _SharedLock = -2;

int _DosVersion;
void* _Allocations;   // the list of all memory blocks, freed at the end

// ---------------------------------------------------------------------------
// Start and end
// ---------------------------------------------------------------------------

// Called by the startup code: opens dos.library, sets up stdout/stderr and the arguments, runs main.
extern "C" int __cs_amiga_main()
{
    unsafe
    {
        void* dos = __exec_OpenLibrary("dos.library".CStr(), 0);
        if (dos == null)
            return 20;
        __cs_amiga_set(_VarDOSBase, (int)(nint)dos);
        _DosVersion = (int)*(uint16*)((uint8*)dos + 20); // lib_Version
        int output = __dos_Output();
        int errors = output;
        if (_DosVersion >= 36)
        {
            int ces = *(int*)((uint8*)__cs_amiga_get(_VarThisTask) + 224); // pr_CES
            if (ces != 0)
                errors = ces;
        }
        __cs_amiga_set(_VarStdout, (int)(nint)_NewFile(output, false));
        __cs_amiga_set(_VarStderr, (int)(nint)_NewFile(errors, false));

        // the arguments: the command line after the program name, split at spaces ("..." keeps spaces)
        char* text = (char*)__cs_amiga_get(_VarArgPtr);
        int length = __cs_amiga_get(_VarArgLen);
        char** argv = (char**)calloc((nuint)(length / 2 + 6), (nuint)4);
        argv[0] = "program".CStr();
        int argc = 1;
        char* copy = (char*)calloc((nuint)(length + 1), (nuint)1);
        int w = 0;
        int i = 0;
        while (text != null && i < length)
        {
            while (i < length && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n'))
                i += 1;
            if (i >= length)
                break;
            argv[argc] = copy + w;
            argc += 1;
            bool quoted = text[i] == '"';
            if (quoted)
                i += 1;
            while (i < length && text[i] != '\n' && (quoted ? text[i] != '"' : (text[i] != ' ' && text[i] != '\t')))
            {
                copy[w] = text[i];
                w += 1;
                i += 1;
            }
            if (quoted && i < length)
                i += 1;
            copy[w] = 0;
            w += 1;
        }
        argv[argc] = null;
        int code = main(argc, argv);
        __cs_amiga_cleanup();
        return code;
    }
}

// Before the program ends: all memory back, dos.library closed.
extern "C" void __cs_amiga_cleanup()
{
    unsafe
    {
        void* block = _Allocations;
        while (block != null)
        {
            void* next = *(void**)block;
            __exec_FreeMem(block, *(int*)((uint8*)block + 8));
            block = next;
        }
        _Allocations = null;
        int dos = __cs_amiga_get(_VarDOSBase);
        if (dos != 0)
        {
            __exec_CloseLibrary((void*)(nint)dos);
            __cs_amiga_set(_VarDOSBase, 0);
        }
    }
}

// ---------------------------------------------------------------------------
// Memory: exec's AllocMem with a header of 16 bytes (next, previous, size), all blocks in one list
// ---------------------------------------------------------------------------

void* _Allocate(nuint size, bool clear)
{
    unsafe
    {
        int total = (int)size + 16;
        void* block = (void*)(nint)__exec_AllocMem(total, clear ? _MemClear : 0);
        if (block == null)
            return null;
        *(void**)block = _Allocations;
        *(void**)((uint8*)block + 4) = null;
        *(int*)((uint8*)block + 8) = total;
        if (_Allocations != null)
            *(void**)((uint8*)_Allocations + 4) = block;
        _Allocations = block;
        return (uint8*)block + 16;
    }
}

extern "C" void* malloc(nuint size) { return _Allocate(size, false); }

extern "C" void* calloc(nuint count, nuint size) { return _Allocate(count * size, true); }

extern "C" void free(void* memory)
{
    unsafe
    {
        if (memory == null)
            return;
        void* block = (uint8*)memory - 16;
        void* next = *(void**)block;
        void* prev = *(void**)((uint8*)block + 4);
        if (prev != null)
            *(void**)prev = next;
        else
            _Allocations = next;
        if (next != null)
            *(void**)((uint8*)next + 4) = prev;
        __exec_FreeMem(block, *(int*)((uint8*)block + 8));
    }
}

extern "C" void* realloc(void* memory, nuint size)
{
    unsafe
    {
        if (memory == null)
            return malloc(size);
        int old = *(int*)((uint8*)memory - 8) - 16;
        void* fresh = malloc(size);
        if (fresh == null)
            return null;
        memcpy(fresh, memory, (nuint)(old < (int)size ? old : (int)size));
        free(memory);
        return fresh;
    }
}

// ---------------------------------------------------------------------------
// Files: a FILE is { dos file handle, close it with fclose }
// ---------------------------------------------------------------------------

void* _NewFile(int handle, bool owned)
{
    unsafe
    {
        int* f = (int*)calloc((nuint)2, (nuint)4);
        f[0] = handle;
        f[1] = owned ? 1 : 0;
        return f;
    }
}

extern "C" void* fopen(char* path, char* mode)
{
    unsafe
    {
        int m = _ModeOldFile;
        if (mode[0] == 'w')
            m = _ModeNewFile;
        else if (mode[0] == 'a')
            m = _ModeReadWrite;
        int handle = __dos_Open(path, m);
        if (handle == 0)
            return null;
        if (mode[0] == 'a')
            __dos_Seek(handle, 0, 1); // OFFSET_END
        return _NewFile(handle, true);
    }
}

extern "C" int fclose(void* file)
{
    unsafe
    {
        if (file == null)
            return -1;
        int* f = (int*)file;
        if (f[1] != 0)
            __dos_Close(f[0]);
        free(file);
        return 0;
    }
}

extern "C" nuint fread(void* buffer, nuint size, nuint count, void* file)
{
    unsafe
    {
        int total = (int)(size * count);
        if (total == 0)
            return 0;
        int got = __dos_Read(((int*)file)[0], buffer, total);
        if (got <= 0)
            return 0;
        return (nuint)got / size;
    }
}

extern "C" nuint fwrite(void* buffer, nuint size, nuint count, void* file)
{
    unsafe
    {
        int total = (int)(size * count);
        if (total == 0)
            return 0;
        int put = __dos_Write(((int*)file)[0], buffer, total);
        if (put <= 0)
            return 0;
        return (nuint)put / size;
    }
}

extern "C" int remove(char* path)
{
    return __dos_DeleteFile(path) != 0 ? 0 : -1;
}

// ---------------------------------------------------------------------------
// Directories: opendir/readdir/closedir on Lock/Examine/ExNext; a dirent has the name at offset 11 (like 32-bit Linux,
// which is what Directory._NameOffset expects)
// ---------------------------------------------------------------------------

// the state of an open directory: [0] the lock, then the FileInfoBlock (260 bytes), then the dirent (11 + 108)
extern "C" void* opendir(char* path)
{
    unsafe
    {
        int lock = __dos_Lock(path, _SharedLock);
        if (lock == 0)
            return null;
        uint8* dir = (uint8*)calloc((nuint)384, (nuint)1);
        *(int*)dir = lock;
        if (__dos_Examine(lock, dir + 4) == 0 || *(int*)(dir + 4 + 4) <= 0)
        {
            __dos_UnLock(lock);
            free(dir);
            return null; // not a directory
        }
        return dir;
    }
}

extern "C" void* readdir(void* handle)
{
    unsafe
    {
        uint8* dir = (uint8*)handle;
        if (__dos_ExNext(*(int*)dir, dir + 4) == 0)
            return null;
        uint8* name = dir + 4 + 8; // fib_FileName
        uint8* entry = dir + 4 + 260;
        int i = 0;
        while (i < 107 && name[i] != 0)
        {
            entry[11 + i] = name[i];
            i += 1;
        }
        entry[11 + i] = 0;
        return entry;
    }
}

extern "C" int closedir(void* handle)
{
    unsafe
    {
        if (handle == null)
            return -1;
        __dos_UnLock(*(int*)handle);
        free(handle);
        return 0;
    }
}

extern "C" int mkdir(char* path, int mode)
{
    int lock = __dos_CreateDir(path);
    if (lock == 0)
        return -1;
    __dos_UnLock(lock);
    return 0;
}

extern "C" char* getcwd(char* buffer, nuint size)
{
    unsafe
    {
        if (_DosVersion < 36)
            return null;
        int lock = __dos_CurrentDir(0);
        __dos_CurrentDir(lock);
        if (__dos_NameFromLock(lock, buffer, (int)size) == 0)
            return null;
        return buffer;
    }
}

// ---------------------------------------------------------------------------
// Environment, commands, time
// ---------------------------------------------------------------------------

char* _EnvBuffer;

extern "C" char* getenv(char* name)
{
    unsafe
    {
        if (_DosVersion < 36)
            return null;
        if (_EnvBuffer == null)
            _EnvBuffer = (char*)malloc((nuint)256);
        if (__dos_GetVar(name, _EnvBuffer, 256, 0) < 0)
            return null;
        return _EnvBuffer;
    }
}

extern "C" int system(char* command)
{
    unsafe
    {
        if (_DosVersion >= 36)
            return __dos_SystemTagList(command, null);
        return __dos_Execute(command, 0, __dos_Output()) != 0 ? 0 : -1;
    }
}

extern "C" void* popen(char* command, char* mode) { return null; }
extern "C" int pclose(void* stream) { return -1; }

// seconds since 1970 (dos counts from 1978)
extern "C" nint time(void* timer)
{
    unsafe
    {
        int* stamp = (int*)calloc((nuint)3, (nuint)4);
        __dos_DateStamp(stamp);
        nint seconds = (nint)(stamp[0] * 86400 + stamp[1] * 60 + stamp[2] / 50 + 252460800);
        free(stamp);
        if (timer != null)
            *(nint*)timer = seconds;
        return seconds;
    }
}

extern "C" int usleep(int microseconds)
{
    __dos_Delay(microseconds / 20000); // ticks of 1/50 s
    return 0;
}

// ---------------------------------------------------------------------------
// printf, fprintf, snprintf: %d %i %u %x %X %c %s %p %% %e %f %g with flags (- 0 + space #), width, precision
// (also *), and the lengths l, ll, h, z. Called from the entries in AmigaRuntime.csh.
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
            void* file = s.Kind == 0 ? (void*)(nint)__cs_amiga_get(_VarStdout) : s.Target;
            __dos_Write(((int*)file)[0], s.Chunk, s.ChunkLength);
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
