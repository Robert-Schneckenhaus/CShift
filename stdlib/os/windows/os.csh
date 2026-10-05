// The operating system layer of the standard library on Windows: the clock, the local time zone, file times,
// renaming, seeking and sleeping (see stdlib/os/posix/os.csh for the same struct on POSIX systems).

namespace System;

extern "C" void GetSystemTimePreciseAsFileTime(void* time);
extern "C" int QueryPerformanceCounter(int64* count);
extern "C" int QueryPerformanceFrequency(int64* frequency);
extern "C" void* _localtime64(int64* time);
extern "C" int GetFileAttributesExA(char* path, int level, void* data);
extern "C" int MoveFileExA(char* from, char* to, uint32 flags);
extern "C" int RemoveDirectoryA(char* path);
extern "C" int _fseeki64(void* file, int64 offset, int origin);
extern "C" int64 _ftelli64(void* file);
extern "C" int fflush(void* file);
extern "C" void Sleep(uint32 milliseconds);

// 100 ns units from 1601-01-01 (FILETIME) to 1970-01-01
const int64 _FileTimeEpoch = 116444736000000000;

struct _Os
{
    // 100 ns units since 1970-01-01 00:00 UTC
    static int64 NowTicks()
    {
        unsafe
        {
            int64 fileTime = 0;
            GetSystemTimePreciseAsFileTime(&fileTime);
            return fileTime - _FileTimeEpoch;
        }
    }

    // 100 ns units from an arbitrary start that never goes back
    static int64 MonotonicTicks()
    {
        unsafe
        {
            int64 count = 0;
            int64 frequency = 0;
            QueryPerformanceCounter(&count);
            QueryPerformanceFrequency(&frequency);
            if (frequency <= 0)
                return 0;
            // count / frequency seconds, without overflowing for long uptimes
            return count / frequency * 10000000 + count % frequency * 10000000 / frequency;
        }
    }

    // local time minus UTC at this moment, in seconds
    static int LocalOffsetSeconds(int64 unixSeconds)
    {
        unsafe
        {
            int64 t = unixSeconds;
            int* tm = (int*)_localtime64(&t); // struct tm: sec, min, hour, mday, mon, year, ...
            if (tm == null)
                return 0;
            int64 local = _Calendar.DaysFromCivil(tm[5] + 1900, tm[4] + 1, tm[3]) * 86400 + tm[2] * 3600 + tm[1] * 60 + tm[0];
            return (int)(local - unixSeconds);
        }
    }

    // the time a file was last written (100 ns units since 1970 UTC)
    static Optional<int64> FileWriteTime(StringSlice path)
    {
        unsafe
        {
            // WIN32_FILE_ATTRIBUTE_DATA: attributes, creation, last access, last write (FILETIME: low, high)
            var data = new uint32[9];
            if (GetFileAttributesExA(path.CStr(), 0, &data[0]) == 0)
                return null;
            int64 fileTime = (int64)data[5] | ((int64)data[6] << 32);
            return fileTime - _FileTimeEpoch;
        }
    }

    // replaces 'to' if it exists (also across drives)
    static bool Rename(StringSlice from, StringSlice to)
    {
        unsafe
        {
            return MoveFileExA(from.CStr(), to.CStr(), 3u) != 0; // MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED
        }
    }

    // an empty directory
    static bool RemoveDirectory(StringSlice path)
    {
        unsafe
        {
            return RemoveDirectoryA(path.CStr()) != 0;
        }
    }

    // origin: 0 the start, 1 the current position, 2 the end
    static bool Seek(void* file, int64 offset, int origin)
    {
        unsafe
        {
            return _fseeki64(file, offset, origin) == 0;
        }
    }

    static int64 Tell(void* file)
    {
        unsafe
        {
            return _ftelli64(file);
        }
    }

    static void Flush(void* file)
    {
        unsafe
        {
            fflush(file);
        }
    }

    static void Wait(int milliseconds)
    {
        unsafe
        {
            if (milliseconds > 0)
                Sleep((uint32)milliseconds);
        }
    }

    // where readdir puts the name in a struct dirent (MinGW-w64: long d_ino, unsigned short d_reclen,
    // unsigned short d_namlen, char d_name[])
    static int DirentNameOffset()
    {
        return 8;
    }
}
