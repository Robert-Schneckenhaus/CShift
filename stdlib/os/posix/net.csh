// The network part of the operating system layer on POSIX systems (Linux, macOS): TCP sockets over IPv4 for
// System.Net (stdlib/net.csh). A socket is a file descriptor; -1 means none.
//
// Linux and macOS (a BSD) differ in a few places, which the program finds out at run time (like
// _Os.DirentNameOffset): struct sockaddr_in starts with a length byte on BSD, the constants of setsockopt differ,
// and struct addrinfo has ai_canonname and ai_addr in the other order. Sending to a connection that the other side
// closed must not end the program with SIGPIPE: Linux takes MSG_NOSIGNAL for each send, macOS SO_NOSIGPIPE for the
// socket. The sockets are not inherited by the programs that Process.Run starts (FD_CLOEXEC).

namespace System.Net;

using System;

extern "C" int socket(int domain, int type, int protocol);
extern "C" int bind(int socket, void* address, uint32 length);
extern "C" int listen(int socket, int backlog);
extern "C" int accept(int socket, void* address, uint32* length);
extern "C" int connect(int socket, void* address, uint32 length);
extern "C" int getsockname(int socket, void* address, uint32* length);
extern "C" int setsockopt(int socket, int level, int name, void* value, uint32 length);
extern "C" int fcntl(int fd, int command, ...);
extern "C" nint send(int socket, void* data, nuint length, int flags);
extern "C" nint recv(int socket, void* buffer, nuint length, int flags);
extern "C" int poll(void* fds, nuint count, int timeout);
extern "C" int close(int fd);
extern "C" int getaddrinfo(char* node, char* service, void* hints, void** result);
extern "C" void freeaddrinfo(void* list);

struct _Net
{
    static bool Supported() { return true; }

    // macOS (and the other BSDs)
    static bool _Bsd()
    {
        return File.Exists("/System/Library/CoreServices/SystemVersion.plist");
    }

    // A listening socket on address:port (the address as a << 24 | b << 16 | c << 8 | d), or -1
    static int64 Listen(uint32 address, int port)
    {
        unsafe
        {
            int s = socket(2, 1, 0); // AF_INET, SOCK_STREAM
            if (s < 0)
                return -1;
            bool bsd = _Bsd();
            _Prepare(s, bsd);
            // SO_REUSEADDR: a server that is started again gets its port at once, while the connections of the last
            // run are in TIME_WAIT
            var one = new int32[1];
            one[0] = 1;
            setsockopt(s, bsd ? 0xFFFF : 1, bsd ? 4 : 2, &one[0], 4);
            var a = _Address(address, port, bsd);
            if (bind(s, &a[0], 16) != 0 || listen(s, 64) != 0)
            {
                close(s);
                return -1;
            }
            return s;
        }
    }

    // the port of a socket (getsockname), 0 if unknown
    static int LocalPort(int64 socket)
    {
        unsafe
        {
            var a = new uint8[16];
            uint32 length = 16;
            if (getsockname((int)socket, &a[0], &length) != 0)
                return 0;
            return (int)a[2] << 8 | (int)a[3];
        }
    }

    static int64 Accept(int64 listener)
    {
        unsafe
        {
            int s = accept((int)listener, null, null);
            if (s < 0)
                return -1;
            _Prepare(s, _Bsd());
            return s;
        }
    }

    static int64 Connect(uint32 address, int port)
    {
        unsafe
        {
            int s = socket(2, 1, 0);
            if (s < 0)
                return -1;
            bool bsd = _Bsd();
            _Prepare(s, bsd);
            var a = _Address(address, port, bsd);
            if (connect(s, &a[0], 16) != 0)
            {
                close(s);
                return -1;
            }
            return s;
        }
    }

    // not inherited by child processes; no SIGPIPE on macOS
    static void _Prepare(int s, bool bsd)
    {
        unsafe
        {
            fcntl(s, 2, 1); // F_SETFD, FD_CLOEXEC
            if (bsd)
            {
                var one = new int32[1];
                one[0] = 1;
                setsockopt(s, 0xFFFF, 0x1022, &one[0], 4); // SOL_SOCKET, SO_NOSIGPIPE
            }
        }
    }

    // struct sockaddr_in: the family (BSD: a length byte, then the family), the port and the address in network byte
    // order, 8 bytes of zeros
    static uint8[] _Address(uint32 address, int port, bool bsd)
    {
        var a = new uint8[16];
        if (bsd)
        {
            a[0] = 16;
            a[1] = 2; // AF_INET
        }
        else
        {
            unsafe
            {
                uint16* family = (uint16*)&a[0];
                family[0] = 2; // AF_INET, in the byte order of the machine
            }
        }
        a[2] = (uint8)(port >> 8 & 255);
        a[3] = (uint8)(port & 255);
        a[4] = (uint8)(address >> 24 & 255u);
        a[5] = (uint8)(address >> 16 & 255u);
        a[6] = (uint8)(address >> 8 & 255u);
        a[7] = (uint8)(address & 255u);
        return a;
    }

    // whether the socket can be read without waiting (data, the end of the connection, an error) or a listener has a
    // connection, within 'milliseconds' (-1: no limit)
    static bool Wait(int64 socket, int milliseconds)
    {
        unsafe
        {
            // struct pollfd { int fd; short events; short revents; }
            var fds = new uint8[8];
            int* fd = (int*)&fds[0];
            fd[0] = (int)socket;
            int16* events = (int16*)&fds[4];
            events[0] = 1; // POLLIN
            if (poll(&fds[0], 1, milliseconds) <= 0)
                return false;
            return events[1] != 0;
        }
    }

    // the bytes that have arrived (at most count), 0 at the end of the connection, -1 on an error
    static int Receive(int64 socket, void* buffer, int count)
    {
        unsafe
        {
            return (int)recv((int)socket, buffer, (nuint)count, 0);
        }
    }

    // MSG_NOSIGNAL on Linux (macOS has SO_NOSIGPIPE on the socket instead)
    static int SendFlags()
    {
        return _Bsd() ? 0 : 0x4000;
    }

    // sends all bytes; false if the connection is lost
    static bool Send(int64 socket, void* data, int count, int flags)
    {
        unsafe
        {
            uint8* bytes = (uint8*)data;
            int sent = 0;
            while (sent < count)
            {
                nint n = send((int)socket, &bytes[sent], (nuint)(count - sent), flags);
                if (n <= 0)
                    return false;
                sent += (int)n;
            }
            return true;
        }
    }

    static void Close(int64 socket)
    {
        unsafe
        {
            close((int)socket);
        }
    }

    // the first IPv4 address of a host name (getaddrinfo), or -1
    static int64 Resolve(StringSlice host)
    {
        unsafe
        {
            // struct addrinfo: ai_flags, ai_family, ai_socktype, ai_protocol (ints), ai_addrlen, then the pointers
            var hints = new uint8[64];
            int* fields = (int*)&hints[0];
            fields[1] = 2; // AF_INET
            fields[2] = 1; // SOCK_STREAM
            void* list = null;
            if (getaddrinfo(host.CStr(), null, &hints[0], &list) != 0 || list == null)
                return -1;
            // ai_addr: after ai_addrlen (64-bit: padded to 8 bytes) on Linux, after ai_canonname on BSD
            bool bsd = _Bsd();
            int at = sizeof(nint) == 8 ? (bsd ? 32 : 24) : (bsd ? 24 : 20);
            uint8* entry = (uint8*)list;
            void** addressField = (void**)&entry[at];
            uint8* a = (uint8*)addressField[0];
            int64 result = -1;
            if (a != null)
                result = (int64)a[4] << 24 | (int64)a[5] << 16 | (int64)a[6] << 8 | (int64)a[7];
            freeaddrinfo(list);
            return result;
        }
    }
}
