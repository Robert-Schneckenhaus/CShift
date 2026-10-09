// cshiftc serve [project | files] [--port <n>] [--host <address>] [--open] [options]: a server for working on a
// program for the browser, like 'ng serve' or 'vite'. It builds the page like 'publish' (a child process: a crash of
// the build does not end the server), serves it on http://localhost:<port>/, watches the files of the project and
// builds again when one changes; the page asks the server for the number of the build twice a second and reloads
// itself when there is a new one. A failed build shows its errors on the page (and in the terminal).
//
// The server has one thread: it waits for connections and data with a time limit (System.Net), so that it can look at
// the files in between. A request is answered when its header has arrived; every answer closes the connection.

namespace CShift.Driver;

using System;
using System.Net;

// A client that has connected: the bytes of its request so far
struct ServeClient
{
    TcpConnection Connection;
    StringBuilder Request;
    Stopwatch Age;
}

// The last build: its number (the page compares it), whether it worked, the page or the output of the compiler
struct ServeBuild
{
    int Number;
    bool Ok;
    string Page;
    string Log;
}

const int ServeDefaultPort = 8080;

int Serve(string[] args, BuildOptions o)
{
    // the project (or the files): what is watched
    var roots = List<string>.Create();
    var ignored = List<string>.Create();
    string name = "";
    if (o.Inputs.Count() > 0 && o.Inputs.Get(0).EndsWith(".csh"))
    {
        foreach (var file in o.Inputs)
            roots.Add(file);
        name = StemOf(o.Inputs.Get(0));
    }
    else
    {
        var loaded = LoadProject(o.Inputs.Count() > 0 ? o.Inputs.Get(0) : "", "wasm32-wasi");
        if (loaded is error loadError)
        {
            Console.WriteErrorLine("error: " + loadError.Message);
            return 1;
        }
        if (loaded is Project project)
        {
            name = project.Name;
            string dir = project.Dir.Length > 0 ? project.Dir : ".";
            roots.Add(dir);
            foreach (var d in project.DependencyDirs)
                roots.Add(d);
            // what builds write: the folder of the output (bin/), unless it is the project folder itself
            string outDir = Path.GetDirectory(project.Output);
            if (outDir.Length > 0 && Path.GetFullPath(outDir) != Path.GetFullPath(dir))
                ignored.Add(Path.GetFullPath(outDir));
        }
    }

    // the port: the given one, or the first free one from 8080 on
    string host = o.ServeHost.Length > 0 ? o.ServeHost : "127.0.0.1";
    TcpListener listener = TcpListener { };
    int tries = o.ServePort > 0 ? 1 : 20;
    int port = o.ServePort > 0 ? o.ServePort : ServeDefaultPort;
    for (var i = 0; i < tries && !listener.IsListening(); i += 1)
    {
        switch (TcpListener.Start(host, port + i))
        {
            case TcpListener started: listener = started; break;
            case NetError.CannotResolve:
                Console.WriteErrorLine("error: '" + host + "' is not an address of this computer (--host)");
                return 1;
            case error e: break;
        }
    }
    if (!listener.IsListening())
    {
        Console.WriteErrorLine("error: cannot listen on port " + port.ToString() + (tries > 1 ? " or the next ones" : "") +
                               " (in use?): --port <n> chooses another one");
        return 1;
    }
    // the folder of the builds (one per port: several servers can run): the page that 'publish' writes there is read
    // and served
    string temp = ServeTempDirectory() + "-" + listener.Port().ToString();
    if (!Directory.Create(temp))
    {
        Console.WriteErrorLine("error: cannot create the folder '" + temp + "'");
        return 1;
    }
    ignored.Add(Path.GetFullPath(temp));
    string pagePath = Path.Combine(temp, "page.html");
    string logPath = Path.Combine(temp, "build.txt");
    string command = ServeBuildCommand(args, pagePath, logPath);
    string url = "http://" + (host == "127.0.0.1" || host == "0.0.0.0" ? "localhost" : host) + ":" + listener.Port().ToString() + "/";

    Console.WriteLine("Serving " + name + " at " + url + " (watching its files; Ctrl+C ends)");
    ServeFlush();
    var build = ServeBuild { Number = 0, Page = "", Log = "" };
    ServeRebuild(ref build, name, command, pagePath, logPath);
    if (o.ServeOpen)
        OpenInBrowser(url);

    var clients = List<ServeClient>.Create();
    var watch = Stopwatch.StartNew();
    int64 fingerprint = Fingerprint(roots, ignored);
    while (true)
    {
        // a new client
        if (listener.Pending(clients.Count() > 0 ? 10 : 50))
        {
            if (listener.Accept() is TcpConnection connection)
                clients.Add(ServeClient { Connection = connection, Request = StringBuilder.Create(), Age = Stopwatch.StartNew() });
        }
        // the requests that have arrived, and the clients that wait too long
        for (var i = clients.Count() - 1; i >= 0; i -= 1)
        {
            var client = clients.Get(i);
            bool done = client.Age.ElapsedMilliseconds() > 10000;
            if (!done && client.Connection.WaitForData(0))
                done = ServeRead(client, build);
            if (done)
            {
                client.Connection.Close();
                clients.RemoveAt(i);
            }
        }
        // a changed file: built again once the files are still for a moment (an editor may save in steps)
        if (watch.ElapsedMilliseconds() >= 300)
        {
            watch.Restart();
            int64 now = Fingerprint(roots, ignored);
            if (now != fingerprint)
            {
                Thread.Sleep(100);
                int64 settled = Fingerprint(roots, ignored);
                while (settled != now)
                {
                    now = settled;
                    Thread.Sleep(100);
                    settled = Fingerprint(roots, ignored);
                }
                fingerprint = now;
                ServeRebuild(ref build, name, command, pagePath, logPath);
            }
        }
    }
    return 0;
}

// Reads what a client sent; once the header of its request is there, answers it. Returns whether the connection is done.
bool ServeRead(ServeClient client, ServeBuild build)
{
    var buffer = new uint8[8192];
    int got = client.Connection.Read(buffer, 0, buffer.Length) is int n ? n : 0;
    if (got <= 0)
        return true; // the client closed the connection (or it broke)
    for (var i = 0; i < got; i += 1)
        client.Request.Append((char)buffer[i]);
    string request = client.Request.ToString();
    if (request.IndexOf("\r\n\r\n") < 0)
    {
        if (request.Length > 65536)
        {
            ServeAnswer(client.Connection, "431 Request Header Fields Too Large", "text/plain", "the request is too large\n", false);
            return true;
        }
        return false;
    }
    // GET /path HTTP/1.1
    var parts = request.Substring(0, request.IndexOf("\r\n")).Split(' ');
    string method = parts.Length > 0 ? parts[0].ToString() : "";
    string target = parts.Length > 1 ? parts[1].ToString() : "/";
    int query = target.IndexOf('?');
    string path = query >= 0 ? target.Substring(0, query) : target;
    bool head = method == "HEAD";
    if (method != "GET" && !head)
        ServeAnswer(client.Connection, "405 Method Not Allowed", "text/plain", "only GET\n", head);
    else if (path == "/" || path == "/index.html")
        ServeAnswer(client.Connection, "200 OK", "text/html; charset=utf-8", ServePage(build), head);
    else if (path == "/__cshift/build")
        ServeAnswer(client.Connection, "200 OK", "text/plain", build.Number.ToString(), head);
    else
        ServeAnswer(client.Connection, "404 Not Found", "text/plain", "not found: " + path + "\n", head);
    return true;
}

void ServeAnswer(TcpConnection connection, string status, string type, string body, bool headOnly)
{
    string header = "HTTP/1.1 " + status + "\r\nContent-Type: " + type + "\r\nContent-Length: " + body.Length.ToString() +
                    "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
    if (connection.WriteText(header) is error)
        return;
    if (!headOnly)
        connection.WriteText(body);
}

// The page of the last build (or its errors), with the script that reloads it after the next build
string ServePage(ServeBuild build)
{
    string reload = ServeReloadScript.Replace("{{build}}", build.Number.ToString());
    string page = build.Ok ? build.Page : ServeErrorPage.Replace("{{log}}", HtmlText(build.Log));
    int end = page.IndexOf("</body>"); // the runtime and the Base64 in the page contain no "</body>"
    return end >= 0 ? page.Substring(0, end) + reload + page.Substring(end) : page + reload;
}

const string ServeReloadScript = "<script>\n" +
    "// cshiftc serve: the page reloads itself after the next build\n" +
    "(() => {\n" +
    "    const build = \"{{build}}\";\n" +
    "    const check = async () => {\n" +
    "        try {\n" +
    "            const answer = await fetch(\"/__cshift/build\", { cache: \"no-store\" });\n" +
    "            if ((await answer.text()).trim() !== build) return location.reload();\n" +
    "        } catch {}\n" +
    "        setTimeout(check, 500);\n" +
    "    };\n" +
    "    setTimeout(check, 500);\n" +
    "})();\n" +
    "</script>\n";

const string ServeErrorPage = "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n" +
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>Build failed</title>\n<style>\n" +
    "    :root { color-scheme: dark; }\n" +
    "    body { margin: 0; padding: 16px; box-sizing: border-box; background: #15171c; color: #d8dbe2; font: 14px/1.4 system-ui, sans-serif; }\n" +
    "    h1 { margin: 0 0 12px; font-size: 16px; color: #ff7b7b; }\n" +
    "    pre { margin: 0; padding: 10px 12px; background: #0d0e12; border: 1px solid #5a2a2e; border-radius: 6px;\n" +
    "          font: 13px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; white-space: pre-wrap; overflow-wrap: anywhere; }\n" +
    "</style>\n</head>\n<body>\n<h1>The build failed: the page reloads when the program is built again</h1>\n<pre>{{log}}</pre>\n</body>\n</html>\n";

// Builds the page with 'publish' in a child process and keeps the result
void ServeRebuild(ref ServeBuild build, string name, string command, string pagePath, string logPath)
{
    var clock = Stopwatch.StartNew();
    if (File.Exists(pagePath))
        File.Delete(pagePath);
    int code = Process.Run(command);
    string log = File.ReadAllText(logPath) is string text ? text : "";
    build.Number += 1;
    build.Ok = false;
    if (code == 0 && File.ReadAllText(pagePath) is string page)
    {
        build.Ok = true;
        build.Page = page;
        build.Log = "";
        Console.WriteLine(ServeTime() + " built " + name + " (" + ((double)clock.ElapsedMilliseconds() / 1000).ToString("F1") + " s)");
        ServeFlush();
        return;
    }
    build.Log = log.Length > 0 ? log : "the compiler ended with exit code " + code.ToString() + "\n";
    Console.WriteLine(ServeTime() + " the build of " + name + " failed:");
    Console.Write(build.Log);
    ServeFlush();
}

// The messages appear at once, also when the output goes to a file or a pipe (like Console.ReadLine does it)
void ServeFlush()
{
    _Os.FlushOutput();
}

// cshiftc publish with the arguments of 'serve' (without its own options), into the folder of the builds
string ServeBuildCommand(string[] args, string pagePath, string logPath)
{
    var command = StringBuilder.Create();
    command.Append(ShellQuote(Host.ExecutablePath()) + " publish");
    for (var i = 1; i < args.Length; i += 1)
    {
        string a = args[i];
        if ((a == "--port" || a == "--host" || a == "-o") && i + 1 < args.Length)
        {
            i += 1;
            continue;
        }
        if (a == "--open")
            continue;
        command.Append(" " + ShellQuote(a));
    }
    command.Append(" -o " + ShellQuote(pagePath) + " > " + ShellQuote(logPath) + " 2>&1");
    return command.ToString();
}

string ShellQuote(string text)
{
    return "\"" + text + "\"";
}

// <temp>/cshift-serve (the port is added): TMPDIR, TEMP or TMP, otherwise /tmp
string ServeTempDirectory()
{
    foreach (var variable in new string[] { "TMPDIR", "TEMP", "TMP" })
    {
        if (Process.GetEnv(variable) is string dir && dir.Length > 0)
            return Path.Combine(dir, "cshift-serve");
    }
    return "/tmp/cshift-serve";
}

// The time of day for the messages: [14:03:27]
string ServeTime()
{
    var now = DateTime.Now();
    return "[" + now.Hour().ToString().PadLeft(2, '0') + ":" + now.Minute().ToString().PadLeft(2, '0') + ":" +
           now.Second().ToString().PadLeft(2, '0') + "]";
}

// Opens the page in the browser of the system (--open)
void OpenInBrowser(string url)
{
    if (Process.IsWindows())
        Process.Run("start \"\" \"" + url + "\"");
    else if (File.Exists("/System/Library/CoreServices/SystemVersion.plist"))
        Process.Run("open \"" + url + "\"");
    else
        Process.Run("xdg-open \"" + url + "\" > /dev/null 2>&1 &");
}

// What the files below the roots look like now: their paths and the times they were written, as one number. Folders
// that start with '.' (.git), node_modules and the ignored folders (the output, the builds) are left out.
int64 Fingerprint(List<string> roots, List<string> ignored)
{
    int64 hash = 17;
    foreach (var root in roots)
    {
        if (Directory.Exists(root))
            hash = FingerprintDirectory(root, ignored, hash);
        else
            hash = FingerprintFile(root, hash);
    }
    return hash;
}

int64 FingerprintDirectory(string dir, List<string> ignored, int64 hash)
{
    if (ignored.Contains(Path.GetFullPath(dir)))
        return hash;
    foreach (var name in Directory.GetEntries(dir))
    {
        if (name.StartsWith(".") || name == "node_modules")
            continue;
        string full = Path.Combine(dir, name);
        if (Directory.Exists(full))
            hash = FingerprintDirectory(full, ignored, hash);
        else
            hash = FingerprintFile(full, hash);
    }
    return hash;
}

int64 FingerprintFile(string file, int64 hash)
{
    int64 written = File.GetLastWriteTimeUtc(file) is DateTime time ? time.Ticks : -1;
    unchecked
    {
        foreach (var c in file)
            hash = hash * 31 + (int64)c;
        return hash * 1000003 + written;
    }
}
