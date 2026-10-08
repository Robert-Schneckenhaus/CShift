// The C library of CShift programs from the wasm backend (added to the program only with --backend wasm): the functions
// the generated code and the standard library use (malloc/free, printf, files, directories, the clock, getenv, ...),
// written on the system interface WASI (wasi_snapshot_preview1). It behaves like wasi-libc where the standard library
// looks at the layout (struct stat, struct dirent: stdlib/os/wasi). printf's formatting is stdlib/libc/format.csh;
// strtod and the math functions are those of the 68000 backend (stdlib/m68k), whose rounding functions and sqrt the
// wasm backend replaces with instructions.
//
// The backend calls __cs_wasm_start (the export _start), and treats some functions specially: __wasi_X is the import X
// of WASI, the __cs_wasm_* functions are instructions, the external globals of the IR (stdout, stderr) are the globals
// of this namespace with the same names.

namespace System.Wasm;

// WASI (wasi_snapshot_preview1): all results are error numbers (0: success)
extern "C" int __wasi_args_sizes_get(void* count, void* size);
extern "C" int __wasi_args_get(void* argv, void* buffer);
extern "C" int __wasi_environ_sizes_get(void* count, void* size);
extern "C" int __wasi_environ_get(void* environ, void* buffer);
extern "C" int __wasi_fd_write(int fd, void* iovs, int count, void* written);
extern "C" int __wasi_fd_read(int fd, void* iovs, int count, void* read);
extern "C" int __wasi_fd_close(int fd);
extern "C" int __wasi_fd_seek(int fd, int64 offset, int whence, void* position);
extern "C" int __wasi_fd_prestat_get(int fd, void* prestat);
extern "C" int __wasi_fd_fdstat_get(int fd, void* fdstat);
extern "C" int __wasi_fd_prestat_dir_name(int fd, void* path, int length);
extern "C" int __wasi_fd_readdir(int fd, void* buffer, int length, int64 cookie, void* used);
extern "C" int __wasi_path_open(int fd, int dirflags, void* path, int length, int oflags, int64 rights, int64 inheriting, int fdflags, void* opened);
extern "C" int __wasi_path_filestat_get(int fd, int flags, void* path, int length, void* filestat);
extern "C" int __wasi_path_filestat_set_times(int fd, int flags, void* path, int length, int64 access, int64 modification, int which);
extern "C" int __wasi_path_create_directory(int fd, void* path, int length);
extern "C" int __wasi_path_remove_directory(int fd, void* path, int length);
extern "C" int __wasi_path_unlink_file(int fd, void* path, int length);
extern "C" int __wasi_path_rename(int fd, void* path, int length, int newFd, void* newPath, int newLength);
extern "C" int __wasi_clock_time_get(int clock, int64 precision, void* time);
extern "C" int __wasi_poll_oneoff(void* subscriptions, void* events, int count, void* done);
extern "C" void __wasi_proc_exit(int code);

// instructions of the backend
extern "C" int __cs_wasm_memory_size();            // in pages of 64 KB
extern "C" int __cs_wasm_memory_grow(int pages);   // the old size, -1 if the memory cannot grow
extern "C" nint __cs_wasm_heap_base();             // where the memory after the globals starts

extern "C" int __main_argc_argv(int argc, char** argv);
extern "C" int __cs_vformat(int kind, void* target, int size, char* format, void* args);
extern "C" void* memset(void* memory, int value, nuint count);
extern "C" void* memcpy(void* dest, void* source, nuint count);

// FILE*: { int fd, int owned (fclose closes the fd) }
void* stdout;
void* stderr;
void* stdin;

// ---------------------------------------------------------------------------
// Start and end
// ---------------------------------------------------------------------------

char** _Environ;
int _EnvCount;

extern "C" void __cs_wasm_start()
{
    unsafe
    {
        stdin = _NewFile(0, false);
        stdout = _NewFile(1, false);
        stderr = _NewFile(2, false);
        _FindPreopens();

        int count = 0;
        int size = 0;
        __wasi_args_sizes_get(&count, &size);
        char** argv = (char**)malloc((nuint)((count + 1) * 4));
        char* text = (char*)malloc((nuint)(size + 1));
        if (count > 0)
            __wasi_args_get(argv, text);
        argv[count] = null;

        int envCount = 0;
        int envSize = 0;
        __wasi_environ_sizes_get(&envCount, &envSize);
        _Environ = (char**)malloc((nuint)((envCount + 1) * 4));
        char* envText = (char*)malloc((nuint)(envSize + 1));
        if (envCount > 0)
            __wasi_environ_get(_Environ, envText);
        _Environ[envCount] = null;
        _EnvCount = envCount;

        int code = __main_argc_argv(count, argv);
        __wasi_proc_exit(code);
    }
}

extern "C" void exit(int code)
{
    __wasi_proc_exit(code);
}

extern "C" char* getenv(char* name)
{
    unsafe
    {
        if (_Environ == null)
            return null;
        for (var i = 0; i < _EnvCount; i += 1)
        {
            char* entry = _Environ[i];
            int k = 0;
            while (name[k] != 0 && entry[k] == name[k])
                k += 1;
            if (name[k] == 0 && entry[k] == '=')
                return entry + k + 1;
        }
        return null;
    }
}

// ---------------------------------------------------------------------------
// Memory: blocks of 2^k bytes (a header of 8 bytes: the class k, the size), a free list per class; bigger blocks
// (from 8 MB) in one list. The memory grows when the heap needs more.
// ---------------------------------------------------------------------------

const int _LargeClass = 23;

uint8* _Heap;  // the heads of the free lists (24 pointers), then the blocks
nint _Brk;     // the end of the used heap
nint _Limit;   // the end of the memory

uint8* _NewBlock(nint total)
{
    unsafe
    {
        if (_Heap == null)
        {
            _Heap = (uint8*)__cs_wasm_heap_base();
            _Brk = (nint)_Heap + 128;
            _Limit = (nint)__cs_wasm_memory_size() * 65536;
        }
        nint block = (_Brk + 15) / 16 * 16;
        if (block + total > _Limit)
        {
            nint missing = block + total - _Limit;
            int pages = (int)((missing + 65535) / 65536);
            if (__cs_wasm_memory_grow(pages) < 0)
                return null;
            _Limit += (nint)pages * 65536;
        }
        _Brk = block + total;
        return (uint8*)block;
    }
}

extern "C" void* malloc(nuint size)
{
    unsafe
    {
        if (_Heap == null)
            _NewBlock(0);
        nint total = (nint)size + 8;
        int k = 4;
        while (k < _LargeClass && ((nint)1 << k) < total)
            k += 1;
        uint8** head = (uint8**)(_Heap + k * 4);
        uint8* block = null;
        if (k < _LargeClass)
        {
            block = *head;
            if (block != null)
                *head = *(uint8**)(block + 8);
            else
                block = _NewBlock((nint)1 << k);
            if (block == null)
                return null;
            *(int*)block = k;
            *(int*)(block + 4) = (int)((nint)1 << k);
            return block + 8;
        }
        // a big block: the first free one that is large enough
        uint8** link = head;
        while (*link != null)
        {
            uint8* candidate = *link;
            if ((nint)*(int*)(candidate + 4) >= total)
            {
                *link = *(uint8**)(candidate + 8);
                return candidate + 8;
            }
            link = (uint8**)(candidate + 8);
        }
        block = _NewBlock(total);
        if (block == null)
            return null;
        *(int*)block = _LargeClass;
        *(int*)(block + 4) = (int)total;
        return block + 8;
    }
}

extern "C" void* calloc(nuint count, nuint size)
{
    unsafe
    {
        void* memory = malloc(count * size);
        if (memory != null)
            memset(memory, 0, count * size);
        return memory;
    }
}

extern "C" void free(void* memory)
{
    unsafe
    {
        if (memory == null)
            return;
        uint8* block = (uint8*)memory - 8;
        uint8** head = (uint8**)(_Heap + *(int*)block * 4);
        *(uint8**)(block + 8) = *head;
        *head = block;
    }
}

// The bytes a block has: all of its size class (__cs_append grows strings in place with it).
extern "C" nuint malloc_usable_size(void* memory)
{
    unsafe
    {
        if (memory == null)
            return 0;
        return (nuint)(*(int*)((uint8*)memory - 4) - 8);
    }
}

extern "C" void* realloc(void* memory, nuint size)
{
    unsafe
    {
        if (memory == null)
            return malloc(size);
        nint capacity = (nint)*(int*)((uint8*)memory - 4) - 8;
        if ((nint)size <= capacity)
            return memory;
        void* fresh = malloc(size);
        if (fresh == null)
            return null;
        memcpy(fresh, memory, (nuint)capacity);
        free(memory);
        return fresh;
    }
}

extern "C" int memcmp(void* a, void* b, nuint count)
{
    unsafe
    {
        uint8* x = (uint8*)a;
        uint8* y = (uint8*)b;
        for (nuint i = 0; i < count; i += 1)
        {
            if (x[i] != y[i])
                return (int)x[i] - (int)y[i];
        }
        return 0;
    }
}

extern "C" int abs(int x)
{
    return x < 0 ? unchecked(-x) : x;
}

extern "C" nuint strlen(char* text)
{
    unsafe
    {
        nuint n = 0;
        while (text[n] != 0)
            n += 1;
        return n;
    }
}

// ---------------------------------------------------------------------------
// Paths: WASI opens files relative to the directories the host gives the program (the preopens); a path is made
// absolute (with the current directory) and goes to the preopen with the longest matching name ("." counts as "/").
// ---------------------------------------------------------------------------

List<int> _PreopenFds;
List<string> _PreopenNames;
List<int64> _PreopenRights;  // the rights of the directory (for directories opened in it)
List<int64> _PreopenInherit; // the rights files opened in it can have (hosts refuse to open a file with more)
string _Cwd;

void _FindPreopens()
{
    unsafe
    {
        _PreopenFds = List<int>.Create();
        _PreopenNames = List<string>.Create();
        _PreopenRights = List<int64>.Create();
        _PreopenInherit = List<int64>.Create();
        _Cwd = "/";
        var fdstat = new int64[3]; // filetype, flags; rights; inheriting rights
        int64 prestat = 0;
        for (var fd = 3; fd < 64; fd += 1)
        {
            if (__wasi_fd_prestat_get(fd, &prestat) != 0)
                break;
            if ((prestat & 255) != 0)
                continue; // not a directory
            int length = (int)(prestat >> 32);
            char* name = (char*)malloc((nuint)(length + 1));
            __wasi_fd_prestat_dir_name(fd, name, length);
            name[length] = 0;
            string text = string.FromCStr(name);
            free(name);
            if (text == "." || text == "./" || text.Length == 0)
                text = "/";
            else if (!text.StartsWith("/"))
                text = "/" + text;
            if (__wasi_fd_fdstat_get(fd, &fdstat[0]) != 0)
                continue;
            _PreopenFds.Add(fd);
            _PreopenNames.Add(_Normalize(text));
            _PreopenRights.Add(fdstat[1]);
            _PreopenInherit.Add(fdstat[2]);
        }
    }
}

// An absolute path without ".", ".." and double slashes.
string _Normalize(string path)
{
    var parts = List<string>.Create();
    foreach (var part in path.Split('/'))
    {
        if (part.Length == 0 || part == ".")
            continue;
        if (part == "..")
        {
            if (parts.Count() > 0)
                parts.RemoveAt(parts.Count() - 1);
            continue;
        }
        parts.Add(part.ToString());
    }
    if (parts.Count() == 0)
        return "/";
    var sb = StringBuilder.Create();
    foreach (var part in parts.ToArray())
        sb.Append("/" + part);
    return sb.ToString();
}

string _Absolute(char* path)
{
    unsafe
    {
        string p = string.FromCStr(path);
        if (p.StartsWith("/"))
            return _Normalize(p);
        return _Normalize(_Cwd + "/" + p);
    }
}

// The preopen of a path (-1: none) and the path relative to it.
int _Resolve(char* path, ref string relative)
{
    int64 rights = 0;
    int64 inherit = 0;
    return _ResolveWithRights(path, ref relative, ref rights, ref inherit);
}

int _ResolveWithRights(char* path, ref string relative, ref int64 rights, ref int64 inherit)
{
    unsafe
    {
        if (_PreopenFds.Count() == 0)
            return -1;
        string full = _Absolute(path);
        int best = -1;
        int bestLength = -1;
        for (var i = 0; i < _PreopenFds.Count(); i += 1)
        {
            string name = _PreopenNames.Get(i);
            if (name != "/" && full != name && !full.StartsWith(name + "/"))
                continue;
            if (name.Length > bestLength)
            {
                best = i;
                bestLength = name.Length;
            }
        }
        if (best < 0)
            return -1;
        string chosen = _PreopenNames.Get(best);
        string rest = chosen == "/" ? full.Substring(1).ToString() : full.Substring(chosen.Length).ToString();
        if (rest.StartsWith("/"))
            rest = rest.Substring(1).ToString();
        relative = rest.Length == 0 ? "." : rest;
        rights = _PreopenRights.Get(best);
        inherit = _PreopenInherit.Get(best);
        return _PreopenFds.Get(best);
    }
}

// Opens a path: the fd, or -1.
int _Open(char* path, int oflags, int fdflags)
{
    unsafe
    {
        string relative = "";
        int64 rights = 0;
        int64 inherit = 0;
        int dir = _ResolveWithRights(path, ref relative, ref rights, ref inherit);
        if (dir < 0)
            return -1;
        int fd = -1;
        int64 own = (oflags & 2) != 0 ? rights : inherit; // a directory, or a file
        if (__wasi_path_open(dir, 1, relative.CStr(), relative.Length, oflags, own, inherit, fdflags, &fd) != 0)
            return -1;
        return fd;
    }
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

void* _NewFile(int fd, bool owned)
{
    unsafe
    {
        int* f = (int*)malloc((nuint)8);
        f[0] = fd;
        f[1] = owned ? 1 : 0;
        return f;
    }
}

// The most bytes one call of fd_read/fd_write moves: node's WASI crashes with very large buffers (80 MB).
const int _Piece = 1048576;

// Writes all bytes to an fd (false: an error).
bool _WriteAll(int fd, uint8* data, int length)
{
    unsafe
    {
        int* iov = (int*)malloc((nuint)8);
        int written = 0;
        bool ok = true;
        while (length > 0)
        {
            iov[0] = (int)(nint)data;
            iov[1] = length < _Piece ? length : _Piece;
            if (__wasi_fd_write(fd, iov, 1, &written) != 0 || written <= 0)
            {
                ok = false;
                break;
            }
            data += written;
            length -= written;
        }
        free(iov);
        return ok;
    }
}

// printf's output (stdlib/libc/format.csh): a file null is stdout
extern "C" void __cs_libc_write(void* file, void* data, int length)
{
    unsafe
    {
        int fd = file == null ? 1 : ((int*)file)[0];
        _WriteAll(fd, (uint8*)data, length);
    }
}

extern "C" void* fopen(char* path, char* mode)
{
    unsafe
    {
        int oflags = 0;  // 'r'
        int fdflags = 0;
        if (mode[0] == 'w')
            oflags = 9;  // creat | trunc
        else if (mode[0] == 'a')
        {
            oflags = 1;  // creat
            fdflags = 1; // append
        }
        int fd = _Open(path, oflags, fdflags);
        if (fd < 0)
            return null;
        return _NewFile(fd, true);
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
            __wasi_fd_close(f[0]);
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
        int* iov = (int*)malloc((nuint)8);
        int got = 0;
        int done = 0;
        while (done < total)
        {
            iov[0] = (int)(nint)buffer + done;
            iov[1] = total - done < _Piece ? total - done : _Piece;
            if (__wasi_fd_read(((int*)file)[0], iov, 1, &got) != 0 || got <= 0)
                break;
            done += got;
        }
        free(iov);
        return (nuint)done / size;
    }
}

// read(fd, buffer, count): at most count bytes of a file descriptor (Console.ReadLine reads the standard input, fd 0)
extern "C" nint read(int fd, void* buffer, nuint count)
{
    unsafe
    {
        int* iov = (int*)malloc((nuint)8);
        int got = 0;
        iov[0] = (int)(nint)buffer;
        iov[1] = (int)count;
        int failed = __wasi_fd_read(fd, iov, 1, &got);
        free(iov);
        return failed != 0 ? (nint)(-1) : (nint)got;
    }
}

extern "C" nuint fwrite(void* buffer, nuint size, nuint count, void* file)
{
    unsafe
    {
        int total = (int)(size * count);
        if (total == 0)
            return 0;
        if (!_WriteAll(((int*)file)[0], (uint8*)buffer, total))
            return 0;
        return count;
    }
}

extern "C" int fflush(void* file)
{
    return 0; // nothing is buffered
}

extern "C" int fseeko(void* file, int64 offset, int origin)
{
    unsafe
    {
        int64 position = 0;
        return __wasi_fd_seek(((int*)file)[0], offset, origin, &position) == 0 ? 0 : -1;
    }
}

extern "C" int64 ftello(void* file)
{
    unsafe
    {
        int64 position = 0;
        if (__wasi_fd_seek(((int*)file)[0], 0, 1, &position) != 0)
            return -1;
        return position;
    }
}

extern "C" int remove(char* path)
{
    unsafe
    {
        string relative = "";
        int dir = _Resolve(path, ref relative);
        if (dir < 0)
            return -1;
        if (__wasi_path_unlink_file(dir, relative.CStr(), relative.Length) == 0)
            return 0;
        return __wasi_path_remove_directory(dir, relative.CStr(), relative.Length) == 0 ? 0 : -1;
    }
}

extern "C" int rename(char* from, char* to)
{
    unsafe
    {
        string a = "";
        string b = "";
        int dirA = _Resolve(from, ref a);
        int dirB = _Resolve(to, ref b);
        if (dirA < 0 || dirB < 0)
            return -1;
        return __wasi_path_rename(dirA, a.CStr(), a.Length, dirB, b.CStr(), b.Length) == 0 ? 0 : -1;
    }
}

// utimensat of wasi-libc for the current directory (AT_FDCWD): the times are struct timespec[2] (seconds, nanoseconds;
// 16 bytes each); a nanosecond value of UTIME_OMIT (-2) keeps a time, UTIME_NOW (-1) sets the current time
extern "C" int utimensat(int dir, char* path, void* times, int flags)
{
    unsafe
    {
        string relative = "";
        int fd = _Resolve(path, ref relative);
        if (fd < 0)
            return -1;
        int64* t = (int64*)times;
        int64 access = 0;
        int64 modification = 0;
        int which = 0; // fstflags: ATIM 1, ATIM_NOW 2, MTIM 4, MTIM_NOW 8
        if (t[1] == -1)
            which |= 2;
        else if (t[1] != -2)
        {
            access = t[0] * 1000000000 + t[1];
            which |= 1;
        }
        if (t[3] == -1)
            which |= 8;
        else if (t[3] != -2)
        {
            modification = t[2] * 1000000000 + t[3];
            which |= 4;
        }
        return __wasi_path_filestat_set_times(fd, 1, relative.CStr(), relative.Length, access, modification, which) == 0 ? 0 : -1;
    }
}

// struct stat of wasi-libc (stdlib/os/wasi): st_mode at 24, st_size at 48, st_mtim at 88 (seconds, nanoseconds)
extern "C" int stat(char* path, void* buffer)
{
    unsafe
    {
        string relative = "";
        int dir = _Resolve(path, ref relative);
        if (dir < 0)
            return -1;
        var filestat = new int64[8]; // dev, ino, filetype, nlink, size, atim, mtim, ctim
        if (__wasi_path_filestat_get(dir, 1, relative.CStr(), relative.Length, &filestat[0]) != 0)
            return -1;
        uint8* st = (uint8*)buffer;
        memset(st, 0, (nuint)120);
        int kind = (int)(filestat[2] & 255);
        *(int*)(st + 24) = kind == 3 ? 16877 : kind == 4 ? 33188 : 0; // S_IFDIR | 0755, S_IFREG | 0644
        *(int64*)(st + 48) = filestat[4];
        *(int64*)(st + 88) = filestat[6] / 1000000000;
        *(int64*)(st + 96) = filestat[6] % 1000000000;
        return 0;
    }
}

// ---------------------------------------------------------------------------
// Directories. A DIR is { fd, cookie of the next entry, bytes in the buffer, position, end reached } (32 bytes), the
// struct dirent readdir returns (d_ino at 0, d_type at 8, d_name at 9: 272 bytes), then the buffer of fd_readdir.
// ---------------------------------------------------------------------------

const int _DirBuffer = 4096;

extern "C" void* opendir(char* path)
{
    unsafe
    {
        int fd = _Open(path, 2, 0); // directory
        if (fd < 0)
            return null;
        uint8* dir = (uint8*)calloc((nuint)(32 + 272 + _DirBuffer), (nuint)1);
        *(int*)dir = fd;
        return dir;
    }
}

extern "C" void* readdir(void* handle)
{
    unsafe
    {
        uint8* dir = (uint8*)handle;
        uint8* entry = dir + 32;
        uint8* buffer = dir + 32 + 272;
        while (true)
        {
            int used = *(int*)(dir + 16);
            int pos = *(int*)(dir + 20);
            bool complete = pos + 24 <= used && pos + 24 + *(int*)(buffer + pos + 16) <= used;
            if (!complete)
            {
                // the next entries from the host, from the cookie of the next one
                if (*(int*)(dir + 24) != 0)
                    return null;
                int got = 0;
                if (__wasi_fd_readdir(*(int*)dir, buffer, _DirBuffer, *(int64*)(dir + 8), &got) != 0 || got == 0)
                    return null;
                *(int*)(dir + 16) = got;
                *(int*)(dir + 20) = 0;
                if (got < _DirBuffer)
                    *(int*)(dir + 24) = 1;
                if (24 > got || 24 + *(int*)(buffer + 16) > got)
                    return null; // an entry larger than the buffer
                continue;
            }
            int length = *(int*)(buffer + pos + 16);
            *(int64*)entry = *(int64*)(buffer + pos + 8);
            entry[8] = buffer[pos + 20];
            int n = length < 255 ? length : 255;
            for (var i = 0; i < n; i += 1)
                entry[9 + i] = buffer[pos + 24 + i];
            entry[9 + n] = 0;
            *(int64*)(dir + 8) = *(int64*)(buffer + pos);
            *(int*)(dir + 20) = pos + 24 + length;
            return entry;
        }
    }
}

extern "C" int closedir(void* handle)
{
    unsafe
    {
        if (handle == null)
            return -1;
        __wasi_fd_close(*(int*)handle);
        free(handle);
        return 0;
    }
}

extern "C" int mkdir(char* path, int mode)
{
    unsafe
    {
        string relative = "";
        int dir = _Resolve(path, ref relative);
        if (dir < 0)
            return -1;
        return __wasi_path_create_directory(dir, relative.CStr(), relative.Length) == 0 ? 0 : -1;
    }
}

extern "C" int rmdir(char* path)
{
    unsafe
    {
        string relative = "";
        int dir = _Resolve(path, ref relative);
        if (dir < 0)
            return -1;
        return __wasi_path_remove_directory(dir, relative.CStr(), relative.Length) == 0 ? 0 : -1;
    }
}

extern "C" char* getcwd(char* buffer, nuint size)
{
    unsafe
    {
        if ((nuint)(_Cwd.Length + 1) > size)
            return null;
        char* text = _Cwd.CStr();
        for (var i = 0; i <= _Cwd.Length; i += 1)
            buffer[i] = text[i];
        return buffer;
    }
}

extern "C" int chdir(char* path)
{
    unsafe
    {
        string full = _Absolute(path);
        var st = new int64[18];
        if (stat(full.CStr(), &st[0]) != 0 || (st[3] & 61440) != 16384) // st_mode (at 24) & S_IFMT == S_IFDIR
            return -1;
        _Cwd = full;
        return 0;
    }
}

// ---------------------------------------------------------------------------
// Time
// ---------------------------------------------------------------------------

// clockid_t is a pointer to the WASI clock's id (like in wasi-libc); a timespec is { int64 seconds, int32 nanoseconds }
extern "C" int clock_gettime(void* clock, void* time)
{
    unsafe
    {
        int64 now = 0;
        if (__wasi_clock_time_get(*(int*)clock, 1, &now) != 0)
            return -1;
        *(int64*)time = now / 1000000000;
        *(int64*)((uint8*)time + 8) = now % 1000000000;
        return 0;
    }
}

extern "C" nint time(void* timer)
{
    unsafe
    {
        int64 now = 0;
        __wasi_clock_time_get(0, 1, &now);
        nint seconds = (nint)(now / 1000000000);
        if (timer != null)
            *(nint*)timer = seconds;
        return seconds;
    }
}

extern "C" int usleep(uint32 microseconds)
{
    unsafe
    {
        // one subscription: a relative timeout of the monotonic clock
        var subscription = new int64[6];
        var events = new int64[4];
        int done = 0;
        subscription[1] = 0;                                // tag: clock
        subscription[2] = 1;                                // the clock's id
        subscription[3] = (int64)microseconds * 1000;       // the timeout in nanoseconds
        subscription[4] = 0;
        subscription[5] = 0;                                // flags: relative
        return __wasi_poll_oneoff(&subscription[0], &events[0], 1, &done) == 0 ? 0 : -1;
    }
}

// ---------------------------------------------------------------------------
// printf, fprintf, snprintf: the backend passes the variable arguments packed (stdlib/libc/format.csh)
// ---------------------------------------------------------------------------

extern "C" int __cs_va_printf(char* format, void* args)
{
    return __cs_vformat(0, null, 0, format, args);
}

extern "C" int __cs_va_fprintf(void* file, char* format, void* args)
{
    return __cs_vformat(1, file, 0, format, args);
}

extern "C" int __cs_va_snprintf(char* buffer, nuint size, char* format, void* args)
{
    return __cs_vformat(2, buffer, (int)size, format, args);
}
