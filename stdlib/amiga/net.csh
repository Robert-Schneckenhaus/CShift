// The network part of the operating system layer on AmigaOS (see stdlib/os/posix/net.csh): the network stacks
// of AmigaOS (bsdsocket.library) are not used yet, so System.Net reports NetError.NotSupported.

namespace System.Net;

using System;

struct _Net
{
    static bool Supported() { return false; }
    static int64 Listen(uint32 address, int port) { return -1; }
    static int LocalPort(int64 socket) { return 0; }
    static int64 Accept(int64 listener) { return -1; }
    static int64 Connect(uint32 address, int port) { return -1; }
    static bool Wait(int64 socket, int milliseconds) { return false; }
    static int Receive(int64 socket, void* buffer, int count) { return -1; }
    static int SendFlags() { return 0; }
    static bool Send(int64 socket, void* data, int count, int flags) { return false; }
    static void Close(int64 socket) { }
    static int64 Resolve(StringSlice host) { return -1; }
}
