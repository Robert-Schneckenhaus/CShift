// The operating system layer of the standard library on WebAssembly (wasm32-wasi, see stdlib/os/posix/os.csh for the
// same struct on POSIX systems). The C library of WASI (wasi-libc) is POSIX-like, but its time_t has 64 bits while
// pointers have 32: a struct timespec is { int64 tv_sec; int32 tv_nsec; } (16 bytes), and st_mtim lies at offset 88 of
// a struct stat. There is no local time zone: the local time is UTC.

namespace System;

extern "C" int clock_gettime(void* clock, void* time); // clockid_t is a pointer to { uint32 id } (the WASI clock)
extern "C" int stat(char* path, void* buffer);
extern "C" int rename(char* from, char* to);
extern "C" int rmdir(char* path);
extern "C" int fseeko(void* file, int64 offset, int origin);
extern "C" int64 ftello(void* file);
extern "C" int fflush(void* file);
extern "C" nint read(int fd, void* buffer, nuint count);
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

    // a struct timespec: the seconds (int64), then the nanoseconds (int32, in the low half of the second int64). The
    // clock is not a number in wasi-libc but a pointer to a struct that holds the WASI clock id (0 realtime,
    // 1 monotonic).
    static int64 _Clock(int clock)
    {
        unsafe
        {
            var id = new int32[1];
            id[0] = clock;
            var ts = new int64[2];
            if (clock_gettime(&id[0], &ts[0]) != 0)
                return 0;
            return ts[0] * 10000000 + (ts[1] & 0xFFFFFFFF) / 100;
        }
    }

    // WASI has no time zones: local time is UTC
    static int LocalOffsetSeconds(int64 unixSeconds)
    {
        return 0;
    }

    // the time a file was last written (100 ns units since 1970 UTC)
    static Optional<int64> FileWriteTime(StringSlice path)
    {
        unsafe
        {
            var buffer = new int64[18]; // struct stat: 144 bytes
            if (stat(path.CStr(), &buffer[0]) != 0)
                return null;
            return buffer[11] * 10000000 + (buffer[12] & 0xFFFFFFFF) / 100; // st_mtim at offset 88
        }
    }

    // replaces 'to' if it exists
    static bool Rename(StringSlice from, StringSlice to)
    {
        unsafe
        {
            return rename(from.CStr(), to.CStr()) == 0;
        }
    }

    // an empty directory
    static bool RemoveDirectory(StringSlice path)
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
            return fseeko(file, offset, origin) == 0;
        }
    }

    static int64 Tell(void* file)
    {
        unsafe
        {
            return ftello(file);
        }
    }

    static void Flush(void* file)
    {
        unsafe
        {
            fflush(file);
        }
    }

    // writes what the C library holds back for stdout (and the other output files), before the program waits for input
    static void FlushOutput()
    {
        unsafe
        {
            fflush(null);
        }
    }

    // the next byte of the standard input, -1 at its end
    static int ReadInputByte()
    {
        unsafe
        {
            uint8 b = 0;
            return read(0, &b, 1) == 1 ? b : -1;
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

    // where readdir puts the name in a struct dirent (wasi-libc: uint64 d_ino, unsigned char d_type, char d_name[])
    static int DirentNameOffset()
    {
        return 9;
    }
}
