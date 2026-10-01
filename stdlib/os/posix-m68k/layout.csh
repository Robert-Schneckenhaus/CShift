// struct stat on m68k Linux (the symbols with a 32-bit time_t; everything is aligned to two bytes), see
// stdlib/os/posix/os.csh.

namespace System;

struct _PosixLayout
{
    static int StatMtime() { return 60; } // the offset of st_mtim (a struct timespec)
}
