// System.Net on WebAssembly: no network, every attempt is NetError.NotSupported (stdlib/os/wasi/net.csh).

using System;
using System.Net;

int Main()
{
    switch (TcpListener.Start("127.0.0.1", 0))
    {
        case NetError e: Console.WriteLine("listen: " + e.ToString()); break;
        default: return 1;
    }
    switch (TcpConnection.Connect("localhost", 80))
    {
        case NetError e: Console.WriteLine("connect: " + e.ToString()); break;
        default: return 2;
    }
    return 0;
}
