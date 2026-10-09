// Standard library: System.Net, a TCP listener and connections on this computer (127.0.0.1).
// skip-target: wasm32 (WebAssembly has no network)
// expect-stdout: listening: true
// expect-stdout: server got: hello
// expect-stdout: client got: HELLO
// expect-stdout: no data yet: false
// expect-stdout: closed: 0
// expect-stdout: refused: CannotConnect
// expect-stdout: in use: CannotListen
// expect-stdout: unresolved: CannotResolve
// expect-stdout: stopped: false

using System;
using System.Net;

string Text(uint8[] bytes, int count)
{
    return Encoding.UTF8().GetString(bytes, 0, count) is string s ? s : "?";
}

int Main()
{
    var listener = TcpListener.Start("127.0.0.1", 0) is TcpListener l ? l : TcpListener { };
    Console.WriteLine("listening: " + listener.IsListening().ToString());
    int port = listener.Port();
    if (port <= 0)
        return 1;
    if (listener.Pending(0))
        return 2; // nobody has connected yet

    // the connection is made by the system (the backlog) before the server takes it
    var client = TcpConnection.Connect("localhost", port) is TcpConnection c ? c : TcpConnection { };
    if (!client.IsOpen())
        return 3;
    if (!listener.Pending(1000))
        return 4;
    var server = listener.Accept() is TcpConnection s ? s : TcpConnection { };
    if (!server.IsOpen())
        return 5;

    var buffer = new uint8[64];
    client.WriteText("hello");
    if (!server.WaitForData(1000))
        return 6;
    int got = server.Read(buffer, 0, buffer.Length) is int n ? n : -1;
    Console.WriteLine("server got: " + Text(buffer, got));
    server.WriteText(Text(buffer, got).ToUpper());
    got = client.Read(buffer, 0, buffer.Length) is int m ? m : -1;
    Console.WriteLine("client got: " + Text(buffer, got));
    Console.WriteLine("no data yet: " + client.WaitForData(50).ToString());

    // the other side closes: the data is read, then Read returns 0
    server.Close();
    if (!client.WaitForData(1000))
        return 7;
    Console.WriteLine("closed: " + (client.Read(buffer, 0, buffer.Length) is int z ? z : -1).ToString());
    client.Close();
    if (client.Read(buffer, 0, 1) is not error)
        return 8;
    // sending to a connection that the other side closed is an error, not the end of the program (SIGPIPE)
    var second = TcpConnection.Connect("127.0.0.1", port) is TcpConnection d ? d : TcpConnection { };
    var taken = listener.Accept() is TcpConnection t ? t : TcpConnection { };
    taken.Close();
    var big = new uint8[1 << 20];
    bool lost = false;
    for (var i = 0; i < 20 && !lost; i += 1)
        lost = second.Write(big) is error;
    if (!lost)
        return 9;
    second.Close();

    switch (TcpConnection.Connect("127.0.0.1", 1))
    {
        case NetError e: Console.WriteLine("refused: " + e.ToString()); break;
        default: return 10;
    }
    switch (TcpListener.Start("127.0.0.1", port))
    {
        case NetError e: Console.WriteLine("in use: " + e.ToString()); break;
        default: return 11;
    }
    switch (TcpConnection.Connect("", port))
    {
        case NetError e: Console.WriteLine("unresolved: " + e.ToString()); break;
        default: return 12;
    }
    listener.Stop();
    Console.WriteLine("stopped: " + listener.IsListening().ToString());
    if (listener.Accept() is not error)
        return 13;
    return 0;
}
