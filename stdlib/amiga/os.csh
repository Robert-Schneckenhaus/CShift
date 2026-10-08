// The operating system layer of the standard library on AmigaOS (see stdlib/os/posix/os.csh for the same struct on
// POSIX systems): on dos.library. AmigaOS keeps the local time without a time zone, so the clock is taken as UTC with
// an offset of 0; its resolution is 1/50 s.

namespace System;

using System.Amiga;

// 100 ns units from 1970-01-01 to 1978-01-01, where the DateStamps of AmigaDOS start
const int64 _AmigaEpoch = 2524608000000000;

struct _Os
{
    // a DateStamp (days, minutes, ticks of 1/50 s) in 100 ns units since 1970
    static int64 _FromDateStamp(int* stamp)
    {
        unsafe
        {
            return _AmigaEpoch + ((int64)stamp[0] * 1440 + stamp[1]) * 600000000 + (int64)stamp[2] * 200000;
        }
    }

    static int64 NowTicks()
    {
        unsafe
        {
            var stamp = new int[3];
            __dos_DateStamp(&stamp[0]);
            return _FromDateStamp(&stamp[0]);
        }
    }

    static int64 MonotonicTicks()
    {
        return NowTicks();
    }

    static int LocalOffsetSeconds(int64 unixSeconds)
    {
        return 0;
    }

    // the time a file was last written: fib_Date of its FileInfoBlock
    static Optional<int64> FileWriteTime(StringSlice path)
    {
        unsafe
        {
            int lockHandle = __dos_Lock(path.CStr(), -2); // SHARED_LOCK
            if (lockHandle == 0)
                return null;
            var info = new int[65]; // a FileInfoBlock (260 bytes, longword aligned)
            bool ok = __dos_Examine(lockHandle, &info[0]) != 0;
            __dos_UnLock(lockHandle);
            if (!ok)
                return null;
            return _FromDateStamp(&info[33]); // fib_Date at offset 132
        }
    }

    // sets when the file (or directory) was last written: 100 ns units since 1970 (dos.library 36)
    static bool SetFileWriteTime(StringSlice path, int64 ticks)
    {
        unsafe
        {
            int64 t = ticks - _AmigaEpoch;
            if (t < 0)
                t = 0;
            var stamp = new int[3];
            stamp[0] = (int)(t / 864000000000);                // days
            stamp[1] = (int)(t % 864000000000 / 600000000);    // minutes
            stamp[2] = (int)(t % 600000000 / 200000);          // ticks of 1/50 s
            return __dos_SetFileDate(path.CStr(), &stamp[0]) != 0;
        }
    }

    // replaces 'to' if it exists
    static bool Rename(StringSlice from, StringSlice to)
    {
        unsafe
        {
            if (__dos_Rename(from.CStr(), to.CStr()) != 0)
                return true;
            // AmigaDOS does not replace: delete the old 'to' and try again
            __dos_DeleteFile(to.CStr());
            return __dos_Rename(from.CStr(), to.CStr()) != 0;
        }
    }

    // an empty directory
    static bool RemoveDirectory(StringSlice path)
    {
        unsafe
        {
            return __dos_DeleteFile(path.CStr()) != 0;
        }
    }

    // origin: 0 the start, 1 the current position, 2 the end (a FILE of stdlib/amiga/libc.csh starts with the handle)
    static bool Seek(void* file, int64 offset, int origin)
    {
        unsafe
        {
            int mode = origin == 0 ? -1 : origin == 1 ? 0 : 1; // OFFSET_BEGINNING, OFFSET_CURRENT, OFFSET_END
            return __dos_Seek(((int*)file)[0], (int)offset, mode) != -1;
        }
    }

    static int64 Tell(void* file)
    {
        unsafe
        {
            return __dos_Seek(((int*)file)[0], 0, 0); // returns the position before the move: here the current one
        }
    }

    static void Flush(void* file)
    {
    }

    // nothing is held back: the C library writes with dos.library directly
    static void FlushOutput()
    {
    }

    // the next byte of the standard input (the process's input handle), -1 at its end
    static int ReadInputByte()
    {
        unsafe
        {
            uint8 b = 0;
            return __dos_Read(__dos_Input(), &b, 1) == 1 ? b : -1;
        }
    }

    static void Wait(int milliseconds)
    {
        if (milliseconds > 0)
            __dos_Delay(milliseconds < 20 ? 1 : milliseconds / 20);
    }

    // where readdir puts the name in a struct dirent (stdlib/amiga/libc.csh: like 32-bit Linux)
    static int DirentNameOffset()
    {
        return 11;
    }
}
