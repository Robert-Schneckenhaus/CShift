// cshiftc publish: a program for the browser in one HTML file. The program is compiled with the wasm backend; the page
// (publish.html) holds it as Base64, the files of "assets" in cshift.json (as Base64 too, put into the file system of
// the program at their path in the project) and the runtime of CShift (web/cshift.js), all embedded in cshc when it is
// compiled. The page works from a web server and as a file (file://): it loads nothing.

namespace CShift.Driver;

using System;

const string PublishPage = embed("publish.html");
const string WebRuntime = embed("../../../web/cshift.js");

// cshiftc publish [project | files] [options]: builds with the wasm backend and writes the page: <output of the
// project>.html (bin/<name>.html), for single files <first file>.html; -o names the page.
int Publish(BuildOptions o)
{
    if ((o.Backend.Length > 0 && o.Backend != "wasm") || (o.Target.Length > 0 && !o.Target.ToLower().StartsWith("wasm32")))
    {
        string given = o.Backend.Length > 0 && o.Backend != "wasm" ? "--backend " + o.Backend : "--target " + o.Target;
        Console.WriteErrorLine("error: 'publish' builds for the browser, with the wasm backend (not " + given + ")");
        return 2;
    }
    if (o.ObjectOnly || o.EmitLlvm || o.EmitAsm || o.Run)
    {
        Console.WriteErrorLine("error: 'publish' writes an HTML file (no -c, --emit-llvm, --emit-asm or --run)");
        return 2;
    }
    string title = "";
    string page = o.Output;
    var assets = List<AssetFile>.Create();
    if (o.Inputs.Count() > 0 && o.Inputs.Get(0).EndsWith(".csh"))
    {
        title = StemOf(o.Inputs.Get(0));
        if (page.Length == 0)
            page = title + ".html";
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
            if (project.Type != "executable")
            {
                Console.WriteErrorLine("error: '" + project.Name + "' is not a program (\"type\": \"" + project.Type + "\"): only programs can be published");
                return 1;
            }
            ApplyProject(ref o, project);
            title = project.Name;
            if (page.Length == 0)
                page = project.Output + ".html";
            var collected = CollectAssets(project.Dir, project.Assets);
            if (collected is error assetError)
            {
                Console.WriteErrorLine("error: " + project.File + ": " + assetError.Message);
                return 1;
            }
            if (collected is List<AssetFile> list)
                assets = list;
        }
    }
    o.Backend = "wasm";
    o.Target = "wasm32-wasi";
    // the program, until it is in the page
    string wasmFile = page + ".wasm";
    o.Output = wasmFile;
    int built = Build(o);
    if (built == 0)
        built = WritePublishedPage(title, wasmFile, assets, page);
    if (File.Exists(wasmFile))
        File.Delete(wasmFile);
    return built;
}

// One file of "assets": where it is, and its path in the file system of the program (relative to the project, with '/')
struct AssetFile
{
    string Source;
    string Path;
}

// The files of the "assets" entries of a project: files and folders (all files below them), relative to the project.
Error<List<AssetFile>> CollectAssets(string projectDir, List<string> entries)
{
    var files = List<AssetFile>.Create();
    string dir = projectDir.Length > 0 ? projectDir : ".";
    foreach (var entry in entries)
    {
        string full = Path.Combine(dir, entry);
        if (Directory.Exists(full))
        {
            foreach (var f in Directory.FindFiles(full, ""))
                files.Add(AssetFile { Source = f, Path = AssetPath(dir, f) });
        }
        else if (File.Exists(full))
            files.Add(AssetFile { Source = full, Path = AssetPath(dir, full) });
        else
            return error("the asset '" + entry + "' does not exist (" + full + ")");
    }
    return files;
}

string AssetPath(string dir, string file)
{
    return Path.GetRelativePath(Path.GetFullPath(dir), Path.GetFullPath(file)).Replace("\\", "/");
}

// The page of a program: 'wasmFile' is the output of the wasm backend.
Error<string> PublishedPage(string title, string wasmFile, List<AssetFile> assets)
{
    var wasm = File.ReadAllBytes(wasmFile);
    if (wasm is error wasmError)
        return error("cannot read '" + wasmFile + "': " + wasmError.Message);
    var assetTags = StringBuilder.Create();
    foreach (var a in assets)
    {
        var data = File.ReadAllBytes(a.Source);
        if (data is error dataError)
            return error("cannot read the asset '" + a.Source + "': " + dataError.Message);
        if (data is uint8[] bytes)
            assetTags.Append("<script type=\"application/octet-stream\" data-asset=\"" + HtmlAttribute(a.Path) + "\">" + Base64(bytes) + "</script>\n");
    }
    if (wasm is uint8[] program)
    {
        // the placeholders, in an order in which no inserted text can contain a later one; "</script" would end the
        // <script> of the runtime early, "<\/script" means the same in JavaScript
        return PublishPage.Replace("{{name}}", HtmlText(title))
                          .Replace("{{assets}}", assetTags.ToString())
                          .Replace("{{wasm}}", Base64(program))
                          .Replace("{{runtime}}", WebRuntime.Replace("</script", "<\\/script"));
    }
    return error("cannot read '" + wasmFile + "'");
}

string HtmlText(string text)
{
    return text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
}

string HtmlAttribute(string text)
{
    return HtmlText(text).Replace("\"", "&quot;");
}

// Base64 (RFC 4648, with padding)
string Base64(uint8[] data)
{
    const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var text = new uint8[(data.Length + 2) / 3 * 4];
    int at = 0;
    int i = 0;
    while (i + 2 < data.Length)
    {
        int bits = (int)data[i] << 16 | (int)data[i + 1] << 8 | (int)data[i + 2];
        text[at] = (uint8)Alphabet[bits >> 18];
        text[at + 1] = (uint8)Alphabet[bits >> 12 & 63];
        text[at + 2] = (uint8)Alphabet[bits >> 6 & 63];
        text[at + 3] = (uint8)Alphabet[bits & 63];
        at += 4;
        i += 3;
    }
    int rest = data.Length - i;
    if (rest > 0)
    {
        int bits = (int)data[i] << 16 | (rest == 2 ? (int)data[i + 1] << 8 : 0);
        text[at] = (uint8)Alphabet[bits >> 18];
        text[at + 1] = (uint8)Alphabet[bits >> 12 & 63];
        text[at + 2] = rest == 2 ? (uint8)Alphabet[bits >> 6 & 63] : (uint8)'=';
        text[at + 3] = (uint8)'=';
    }
    return Encoding.ASCII().GetString(text) is string s ? s : "";
}

// Writes the page of a program, built into 'wasmFile' by the wasm backend; returns the exit code.
int WritePublishedPage(string title, string wasmFile, List<AssetFile> assets, string htmlPath)
{
    var page = PublishedPage(title, wasmFile, assets);
    if (page is error pageError)
    {
        Console.WriteErrorLine("error: " + pageError.Message);
        return 1;
    }
    if (page is string html)
    {
        if (WriteOutput(htmlPath, html) != 0)
            return 1;
        Console.WriteLine("Published " + htmlPath + " (" + SizeText(html.Length) + "): open it in a browser");
        return 0;
    }
    return 1;
}

string SizeText(int bytes)
{
    if (bytes < 1024 * 1024)
        return ((bytes + 1023) / 1024).ToString() + " KB";
    return ((double)bytes / (1024 * 1024)).ToString("F1") + " MB";
}
