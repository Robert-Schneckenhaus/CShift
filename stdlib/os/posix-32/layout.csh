// struct stat on 32-bit POSIX systems (i386, powerpc, ...; the symbols with a 32-bit time_t), see
// stdlib/os/posix/os.csh.

namespace System;

struct _PosixLayout
{
    static int StatMtime() { return 64; } // the offset of st_mtim (a struct timespec)
}
