// The operating system layer of the standard library on POSIX systems (Linux, ...): the clock, the local time zone,
// file times, renaming, seeking and sleeping, for DateTime, Stopwatch, FileStream, File and Directory. The same struct
// exists for Windows (stdlib/os/windows) and AmigaOS (stdlib/amiga/os.csh); the compiler adds the one of the target.
// The layouts of struct stat differ between architectures: _PosixLayout (stdlib/os/posix-64, -32, -m68k).

namespace System;

extern "C" int clock_gettime(int clock, void* time);
extern "C" void* localtime_r(nint* time, void* tm);
extern "C" int stat(char* path, void* buffer);
extern "C" int rename(char* from, char* to);
extern "C" int rmdir(char* path);
extern "C" int fseeko64(void* file, int64 offset, int origin);
extern "C" int64 ftello64(void* file);
extern "C" int fflush(void* file);
extern "C" int usleep(uint32 microseconds);

struct _Os
{
    // 100 ns units since 1970-01-01 00:00 UTC
    static int64 NowTicks()
    {
        return _Clock(0); // CLOCK_REALTIME
    }

    // 100 ns units from an arbitrary start that never goes back
    static int64 MonotonicTicks()
    {
        return _Clock(1); // CLOCK_MONOTONIC
    }

    // a struct timespec is { time_t, long }: two nint
    static int64 _Clock(int clock)
    {
        unsafe
        {
            var ts = new nint[2];
            if (clock_gettime(clock, &ts[0]) != 0)
                return 0;
            return (int64)ts[0] * 10000000 + (int64)ts[1] / 100;
        }
    }

    // local time minus UTC at this moment, in seconds
    static int LocalOffsetSeconds(int64 unixSeconds)
    {
        unsafe
        {
            nint t = (nint)unixSeconds;
            var tm = new int[16]; // struct tm: sec, min, hour, mday, mon, year, ... (and more on some systems)
            if (localtime_r(&t, &tm[0]) == null)
                return 0;
            int64 local = _Calendar.DaysFromCivil(tm[5] + 1900, tm[4] + 1, tm[3]) * 86400 + tm[2] * 3600 + tm[1] * 60 + tm[0];
            return (int)(local - unixSeconds);
        }
    }

    // the time a file was last written (100 ns units since 1970 UTC)
    static Optional<int64> FileWriteTime(string path)
    {
        unsafe
        {
            var buffer = new uint8[256];
            if (stat(path.CStr(), &buffer[0]) != 0)
                return null;
            nint* mtime = (nint*)&buffer[_PosixLayout.StatMtime()]; // struct timespec st_mtim
            return (int64)mtime[0] * 10000000 + (int64)mtime[1] / 100;
        }
    }

    // replaces 'to' if it exists
    static bool Rename(string from, string to)
    {
        unsafe
        {
            return rename(from.CStr(), to.CStr()) == 0;
        }
    }

    // an empty directory
    static bool RemoveDirectory(string path)
    {
        unsafe
        {
            return rmdir(path.CStr()) == 0;
        }
    }

    // origin: 0 the start, 1 the current position, 2 the end
    static bool Seek(void* file, int64 offset, int origin)
    {
        unsafe
        {
            return fseeko64(file, offset, origin) == 0;
        }
    }

    static int64 Tell(void* file)
    {
        unsafe
        {
            return ftello64(file);
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
        while (milliseconds > 0)
        {
            int part = milliseconds > 1000 ? 1000 : milliseconds;
            usleep((uint32)part * 1000u);
            milliseconds -= part;
        }
    }
}
