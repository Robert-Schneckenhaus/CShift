// struct stat on 64-bit POSIX systems (x86_64, aarch64, ...), see stdlib/os/posix/os.csh.

namespace System;

struct _PosixLayout
{
    static int StatMtime() { return 88; } // the offset of st_mtim (a struct timespec)
}
