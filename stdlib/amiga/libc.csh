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
extern "C" int __dos_Rename(char* from, char* to);
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
extern "C" int* __cs_amiga_libtable();
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

        if (!_OpenLibraries(errors))
        {
            __cs_amiga_cleanup();
            return 20;
        }

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

// Opens the libraries the program calls (imported from SFD files); false (and a message) if one is missing.
bool _OpenLibraries(int errors)
{
    unsafe
    {
        int* libs = __cs_amiga_libtable();
        for (var k = 0; libs[k] != 0; k += 2)
        {
            char* libName = (char*)(nint)libs[k];
            void* libBase = __exec_OpenLibrary(libName, 0);
            if (libBase == null)
            {
                string message = "cannot open " + string.FromCStr(libName) + "\n";
                __dos_Write(errors, message.CStr(), message.Length);
                return false;
            }
            *(void**)(nint)libs[k + 1] = libBase;
        }
        return true;
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
        int* libs = __cs_amiga_libtable();
        for (var k = 0; libs[k] != 0; k += 2)
        {
            void** slot = (void**)(nint)libs[k + 1];
            if (*slot != null)
            {
                __exec_CloseLibrary(*slot);
                *slot = null;
            }
        }
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

// The bytes a block has (what was asked for: AllocMem gives exactly that); __cs_append grows strings in place with it.
extern "C" nuint malloc_usable_size(void* memory)
{
    unsafe
    {
        if (memory == null)
            return 0;
        return (nuint)(*(int*)((uint8*)memory - 8) - 16);
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
// Output for printf (stdlib/libc/format.csh): a file null is stdout
// ---------------------------------------------------------------------------

extern "C" void __cs_libc_write(void* file, void* data, int length)
{
    unsafe
    {
        if (file == null)
            file = (void*)(nint)__cs_amiga_get(_VarStdout);
        __dos_Write(((int*)file)[0], data, length);
    }
}
