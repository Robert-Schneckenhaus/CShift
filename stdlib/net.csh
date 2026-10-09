// Network connections over TCP (IPv4): TcpListener (a server) and TcpConnection. The operating system's part is _Net,
// with one version per layer: stdlib/os/posix/net.csh (Linux, macOS), stdlib/os/windows/net.csh, and the ones of
// WebAssembly (stdlib/os/wasi/net.csh) and AmigaOS (stdlib/amiga/net.csh), which have no network.

namespace System.Net;

using System;

//! Network connections over TCP (IPv4): [TcpListener] waits for the connections of clients, [TcpConnection] connects to
//! a server; both send and receive bytes. Windows, Linux and macOS; on WebAssembly and AmigaOS every attempt is
//! [NetError.NotSupported].

/// The errors of network connections ([TcpListener], [TcpConnection]).
///
/// ```
/// switch (TcpConnection.Connect("localhost", 8080))
/// {
///     case TcpConnection connection: ...; break;
///     case NetError.CannotConnect: Console.WriteLine("the server does not run"); break;
///     case error e: Console.WriteLine(e.Message); break;
/// }
/// ```
error NetError
{
    /// The name of the host is unknown (or there is no network), or the address is not an IPv4 address.
    CannotResolve = 1,
    /// Nothing listens on the port of the host, or the host cannot be reached.
    CannotConnect = 2,
    /// The port is in use (by another program), or the program may not listen on it.
    CannotListen = 3,
    /// The connection or the listener is closed, or sending or receiving failed (the other side reset the
    /// connection).
    ConnectionLost = 4,
    /// The platform has no network connections: WebAssembly and AmigaOS.
    NotSupported = 5
}

/// A TCP server: listens on a port and accepts the connections of clients, each a [TcpConnection].
///
/// ```
/// using System;
/// using System.Net;
///
/// using var listener = try TcpListener.Start("127.0.0.1", 8080);
/// while (true)
/// {
///     using var client = try listener.Accept();
///     var request = new uint8[4096];
///     int got = try client.Read(request, 0, request.Length);
///     try client.WriteText("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nHello\n");
/// }
/// ```
///
/// [TcpListener.Pending] and [TcpConnection.WaitForData] wait with a time limit: one thread can serve several
/// connections and do other work in between. Like a [FileStream], a listener is a struct around a handle of the
/// operating system: copies of it share the handle, and [TcpListener.Stop] of one stops all of them; keep one owner.
/// The zero value (`TcpListener { }`) is a stopped listener. Only IPv4.
struct TcpListener : IDisposable
{
    int64 _socket;
    bool _open;
    int _port;

    /// Listens on `port` of `address`: `"127.0.0.1"` (or `"localhost"`) accepts the connections from this computer
    /// only, `"0.0.0.0"` those from every network. Port 0 takes a free port; [TcpListener.Port] says which one.
    /// @error NetError.CannotResolve `address` is not an IPv4 address (or a name for one).
    /// @error NetError.CannotListen the port is in use, or the program may not listen on it (ports below 1024 on
    /// Linux and macOS).
    /// @error NetError.NotSupported WebAssembly and AmigaOS.
    /// @panics when `port` is not in 0..65535.
    static NetError<TcpListener> Start(StringSlice address, int port)
    {
        _CheckPort("TcpListener.Start", port);
        if (!_Net.Supported())
            return error("there are no network connections on this platform", NetError.NotSupported);
        int64 ip = _ResolveIPv4(address);
        if (ip < 0)
            return error("cannot resolve '" + address + "' (an IPv4 address)", NetError.CannotResolve);
        int64 socket = _Net.Listen((uint32)ip, port);
        if (socket < 0)
            return error("cannot listen on " + address + ":" + port.ToString() + " (is the port in use?)", NetError.CannotListen);
        return TcpListener { _socket = socket, _open = true, _port = _Net.LocalPort(socket) };
    }

    /// Whether it listens (it is not stopped).
    bool IsListening() { return _open; }

    /// The port it listens on: the one given to [TcpListener.Start], or the free one that the system chose for port 0.
    int Port() { return _port; }

    /// Waits up to `milliseconds` for a client to connect (0: does not wait; -1: waits as long as it takes).
    /// @returns whether a connection is waiting: [TcpListener.Accept] then takes it without waiting.
    bool Pending(int milliseconds)
    {
        if (!IsListening())
            return false;
        return _Net.Wait(_socket, milliseconds);
    }

    /// Takes the next connection of a client; waits for one if none is [TcpListener.Pending].
    /// @error NetError.ConnectionLost the listener is stopped, or taking the connection failed.
    NetError<TcpConnection> Accept()
    {
        if (!IsListening())
            return error("the listener is stopped", NetError.ConnectionLost);
        int64 socket = _Net.Accept(_socket);
        if (socket < 0)
            return error("cannot accept a connection", NetError.ConnectionLost);
        return TcpConnection.FromSocket(socket);
    }

    /// Stops listening; the connections that it accepted stay open. Stopping again does nothing.
    void Stop()
    {
        if (_open)
            _Net.Close(_socket);
        _open = false;
        _port = 0;
    }

    /// Stops listening ([TcpListener.Stop]); `using` calls it.
    void Dispose()
    {
        Stop();
    }
}

/// A TCP connection: bytes in both directions, to a server ([TcpConnection.Connect]) or from a client
/// ([TcpListener.Accept]).
///
/// ```
/// using var connection = try TcpConnection.Connect("example.com", 80);
/// try connection.WriteText("GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n");
/// var buffer = new uint8[4096];
/// while (true)
/// {
///     int got = try connection.Read(buffer, 0, buffer.Length);
///     if (got == 0)
///         break; // the server closed the connection
///     Console.Write(try Encoding.UTF8().GetString(buffer, 0, got));
/// }
/// ```
///
/// Copies of a connection share it, and [TcpConnection.Close] of one closes it for all of them; keep one owner. The
/// zero value (`TcpConnection { }`) is a closed connection. Only IPv4.
struct TcpConnection : IDisposable
{
    int64 _socket;
    bool _open;
    int _flags; // the flags of _Net.Send for this platform

    /// Connects to `port` of `host`: a name (`"example.com"`, `"localhost"`) or an IPv4 address (`"192.168.1.10"`).
    /// @error NetError.CannotResolve the name is unknown (or there is no network).
    /// @error NetError.CannotConnect nothing listens on the port, or the host cannot be reached.
    /// @error NetError.NotSupported WebAssembly and AmigaOS.
    /// @panics when `port` is not in 0..65535.
    static NetError<TcpConnection> Connect(StringSlice host, int port)
    {
        _CheckPort("TcpConnection.Connect", port);
        if (!_Net.Supported())
            return error("there are no network connections on this platform", NetError.NotSupported);
        int64 ip = _ResolveIPv4(host);
        if (ip < 0)
            return error("cannot resolve '" + host + "' (no IPv4 address)", NetError.CannotResolve);
        int64 socket = _Net.Connect((uint32)ip, port);
        if (socket < 0)
            return error("cannot connect to " + host + ":" + port.ToString(), NetError.CannotConnect);
        return FromSocket(socket);
    }

    /// A connection around a socket of the operating system ([TcpListener.Accept]).
    /// @internal
    static TcpConnection FromSocket(int64 socket)
    {
        return TcpConnection { _socket = socket, _open = true, _flags = _Net.SendFlags() };
    }

    /// Whether the connection is open (not closed yet by [TcpConnection.Close]). That the other side closed it shows
    /// when [TcpConnection.Read] returns 0.
    bool IsOpen() { return _open; }

    /// Waits up to `milliseconds` until [TcpConnection.Read] can return without waiting: data arrived, or the other
    /// side closed the connection (0: does not wait; -1: waits as long as it takes).
    /// @returns whether [TcpConnection.Read] would return at once; `false` when the time is up (or the connection is
    /// closed).
    bool WaitForData(int milliseconds)
    {
        if (!_open)
            return false;
        return _Net.Wait(_socket, milliseconds);
    }

    /// Reads what has arrived, up to `count` bytes, into `buffer[offset..]`; waits until something arrives.
    /// @returns the number of bytes; 0 when the other side closed the connection and everything was read.
    /// @error NetError.ConnectionLost the connection is closed, or the other side reset it.
    /// @panics when `offset..offset + count` is not inside of `buffer`.
    NetError<int> Read(uint8[] buffer, int offset, int count)
    {
        if (offset < 0 || count < 0 || offset + count > buffer.Length)
            Environment.Panic("TcpConnection.Read: the range " + offset.ToString() + ".." + (offset + count).ToString() +
                              " is outside the buffer (length " + buffer.Length.ToString() + ")");
        if (!_open)
            return error("the connection is closed", NetError.ConnectionLost);
        if (count == 0)
            return 0;
        int got = 0;
        unsafe
        {
            got = _Net.Receive(_socket, &buffer[offset], count);
        }
        if (got < 0)
            return error("the connection was lost", NetError.ConnectionLost);
        return got;
    }

    /// Sends all of `bytes`: an array, a part of one, or the bytes of a text (`text.AsBytes()`).
    /// @error NetError.ConnectionLost the connection is closed, or the other side closed or reset it.
    NetError<void> Write(ReadOnlySlice<uint8> bytes)
    {
        if (!_open)
            return error("the connection is closed", NetError.ConnectionLost);
        if (bytes.Length == 0)
            return;
        bool sent = false;
        unsafe
        {
            sent = _Net.Send(_socket, bytes.Ptr(), bytes.Length, _flags);
        }
        if (!sent)
            return error("the connection was lost", NetError.ConnectionLost);
        return;
    }

    /// Sends `text` as UTF-8 bytes.
    /// @error NetError.ConnectionLost the connection is closed, or the other side closed or reset it.
    NetError<void> WriteText(StringSlice text)
    {
        return Write(text.AsBytes());
    }

    /// Closes the connection; the copies of it are closed as well. Closing it again does nothing.
    void Close()
    {
        if (_open)
            _Net.Close(_socket);
        _open = false;
    }

    /// Closes the connection ([TcpConnection.Close]); `using` calls it.
    void Dispose()
    {
        Close();
    }
}

void _CheckPort(string function, int port)
{
    if (port < 0 || port > 65535)
        Environment.Panic(function + ": the port " + port.ToString() + " is not in 0..65535");
}

// The IPv4 address of a host as a.b.c.d = a << 24 | b << 16 | c << 8 | d, or -1: the address itself, "localhost", or
// a name that the operating system knows
int64 _ResolveIPv4(StringSlice host)
{
    if (host == "localhost")
        return 0x7F000001;
    int64 numeric = _ParseIPv4(host);
    if (numeric >= 0)
        return numeric;
    if (host.Length == 0)
        return -1;
    return _Net.Resolve(host);
}

// "a.b.c.d" with four numbers of 0..255, or -1
int64 _ParseIPv4(StringSlice text)
{
    int64 address = 0;
    int parts = 0;
    int i = 0;
    while (parts < 4)
    {
        int digits = 0;
        int value = 0;
        while (i < text.Length && text[i] >= '0' && text[i] <= '9' && digits < 4)
        {
            value = value * 10 + ((int)text[i] - 48);
            digits += 1;
            i += 1;
        }
        if (digits == 0 || digits > 3 || value > 255)
            return -1;
        address = address * 256 + value;
        parts += 1;
        if (parts < 4)
        {
            if (i >= text.Length || text[i] != '.')
                return -1;
            i += 1;
        }
    }
    return i == text.Length ? address : -1;
}
