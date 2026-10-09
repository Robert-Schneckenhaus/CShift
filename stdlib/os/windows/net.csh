// The network part of the operating system layer on Windows: TCP sockets over IPv4 (Winsock, ws2_32) for System.Net
// (stdlib/net.csh); see stdlib/os/posix/net.csh for the same struct on POSIX systems. A SOCKET is a pointer-sized
// handle; INVALID_SOCKET (all bits set) is -1. Winsock is started before the first socket (WSAStartup counts the
// calls, so it may be called for each one). The sockets are not inherited by the programs that Process.Run starts.

namespace System.Net;

using System;

link "ws2_32";

extern "C" int WSAStartup(uint16 version, void* data);
extern "C" nint socket(int family, int type, int protocol);
extern "C" int bind(nint socket, void* address, int length);
extern "C" int listen(nint socket, int backlog);
extern "C" nint accept(nint socket, void* address, int* length);
extern "C" int connect(nint socket, void* address, int length);
extern "C" int getsockname(nint socket, void* address, int* length);
extern "C" int send(nint socket, void* data, int length, int flags);
extern "C" int recv(nint socket, void* buffer, int length, int flags);
extern "C" int closesocket(nint socket);
extern "C" int WSAPoll(void* fds, uint32 count, int timeout);
extern "C" int getaddrinfo(char* node, char* service, void* hints, void** result);
extern "C" void freeaddrinfo(void* list);
extern "C" int SetHandleInformation(void* handle, uint32 mask, uint32 flags);

struct _Net
{
    static bool Supported() { return true; }

    static void _Start()
    {
        unsafe
        {
            var data = new uint8[512]; // WSADATA
            WSAStartup(0x0202, &data[0]); // version 2.2
        }
    }

    // A listening socket on address:port (the address as a << 24 | b << 16 | c << 8 | d), or -1. Without
    // SO_REUSEADDR: on Windows it would let a second server take the same port.
    static int64 Listen(uint32 address, int port)
    {
        unsafe
        {
            _Start();
            nint s = socket(2, 1, 6); // AF_INET, SOCK_STREAM, IPPROTO_TCP
            if (s == -1)
                return -1;
            _Prepare(s);
            var a = _Address(address, port);
            if (bind(s, &a[0], 16) != 0 || listen(s, 64) != 0)
            {
                closesocket(s);
                return -1;
            }
            return (int64)s;
        }
    }

    // the port of a socket (getsockname), 0 if unknown
    static int LocalPort(int64 socket)
    {
        unsafe
        {
            var a = new uint8[16];
            int length = 16;
            if (getsockname((nint)socket, &a[0], &length) != 0)
                return 0;
            return (int)a[2] << 8 | (int)a[3];
        }
    }

    static int64 Accept(int64 listener)
    {
        unsafe
        {
            nint s = accept((nint)listener, null, null);
            if (s == -1)
                return -1;
            _Prepare(s);
            return (int64)s;
        }
    }

    static int64 Connect(uint32 address, int port)
    {
        unsafe
        {
            _Start();
            nint s = socket(2, 1, 6);
            if (s == -1)
                return -1;
            _Prepare(s);
            var a = _Address(address, port);
            if (connect(s, &a[0], 16) != 0)
            {
                closesocket(s);
                return -1;
            }
            return (int64)s;
        }
    }

    // not inherited by child processes (HANDLE_FLAG_INHERIT)
    static void _Prepare(nint s)
    {
        unsafe
        {
            SetHandleInformation((void*)s, 1, 0);
        }
    }

    // struct sockaddr_in: the family (little endian), the port and the address in network byte order, 8 zeros
    static uint8[] _Address(uint32 address, int port)
    {
        var a = new uint8[16];
        a[0] = 2; // AF_INET
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
            // WSAPOLLFD { SOCKET fd; short events; short revents; }, padded to the size of a pointer
            var fds = new uint8[16];
            nint* fd = (nint*)&fds[0];
            fd[0] = (nint)socket;
            int16* events = (int16*)&fds[sizeof(nint)];
            events[0] = 0x0300; // POLLIN (POLLRDNORM | POLLRDBAND)
            if (WSAPoll(&fds[0], 1, milliseconds) <= 0)
                return false;
            return events[1] != 0;
        }
    }

    // the bytes that have arrived (at most count), 0 at the end of the connection, -1 on an error
    static int Receive(int64 socket, void* buffer, int count)
    {
        unsafe
        {
            return recv((nint)socket, buffer, count, 0);
        }
    }

    // Windows has no SIGPIPE
    static int SendFlags()
    {
        return 0;
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
                int n = send((nint)socket, &bytes[sent], count - sent, flags);
                if (n <= 0)
                    return false;
                sent += n;
            }
            return true;
        }
    }

    static void Close(int64 socket)
    {
        unsafe
        {
            closesocket((nint)socket);
        }
    }

    // the first IPv4 address of a host name (getaddrinfo), or -1
    static int64 Resolve(StringSlice host)
    {
        unsafe
        {
            _Start();
            // struct addrinfo: ai_flags, ai_family, ai_socktype, ai_protocol (ints), ai_addrlen (size_t),
            // ai_canonname, ai_addr, ai_next
            var hints = new uint8[64];
            int* fields = (int*)&hints[0];
            fields[1] = 2; // AF_INET
            fields[2] = 1; // SOCK_STREAM
            void* list = null;
            if (getaddrinfo(host.CStr(), null, &hints[0], &list) != 0 || list == null)
                return -1;
            int at = 16 + sizeof(nint) * 2;
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
