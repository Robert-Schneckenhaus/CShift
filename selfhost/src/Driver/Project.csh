// Projects: the file cshift.json.
//
//   { "name": "demo", "version": "0.1.0", "type": "executable", "sources": ["src"], "output": "bin/demo",
//     "optimize": 2, "links": [], "includePaths": [], "libraryPaths": [], "defines": [], "ffiApi": [], "target": "",
//     "unchecked": false, "debug": false, "dependencies": ["../mylib"], "assets": ["data"] }
//
// Only "name" is required. Paths are relative to the project file. A dependency is a project with "type": "library";
// its sources, libraries, include paths, defines and ffiApi entries become a part of the project that uses it.

namespace CShift.Driver;

using System;

struct Project
{
    string File;                 // path of cshift.json
    string Dir;                  // directory of cshift.json ("" = current directory)
    string Name;
    string Version;
    string Type;                 // "executable", "object" or "library"
    List<string> Sources;        // .csh files, sorted
    string Output;               // output path (without the extension of the platform)
    int Optimize;
    bool HasOptimize;
    List<string> Links;          // library names for the linker (-l<name>)
    List<string> LinkFiles;      // library and object files for the linker
    List<string> IncludePaths;
    List<string> LibraryPaths;
    List<string> Defines;
    List<string> ApiPaths;
    string Target;               // target triple, "" = host
    bool Unchecked;              // integer overflow wraps instead of a panic
    bool Debug;                  // debug information (-g)
    string Backend;              // "llvm", "m68k", "wasm" or "" (the target's default)
    string Ndk;                  // the AmigaOS NDK (a path relative to the project)
    List<string> Assets;         // files and folders that "cshiftc publish" puts into the page (relative to the project)
    List<string> DependencyDirs; // the folders of the libraries in "dependencies" (also theirs), for "cshiftc serve"
}

bool ValidProjectName(string name)
{
    if (name.Length == 0)
        return false;
    for (var i = 0; i < name.Length; i += 1)
    {
        char c = name[i];
        bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.';
        if (!ok)
            return false;
    }
    return true;
}

// The project file for 'location': a directory with cshift.json, a project file, or "" to search the current directory
// and its parents.
Error<string> FindProjectFile(string location)
{
    if (location.Length > 0)
    {
        string file = Directory.Exists(location) ? Path.Combine(location, "cshift.json") : location;
        if (!File.Exists(file))
            return error("cannot find project file '" + file + "'");
        return file;
    }
    string prefix = "";
    for (var level = 0; level < 32; level += 1)
    {
        string candidate = prefix + "cshift.json";
        if (File.Exists(candidate))
            return candidate;
        prefix += "../";
    }
    return error("no cshift.json found in the current directory or any parent directory");
}

// A source entry is a .csh file or a directory that is searched recursively for .csh files.
Error<void> AddSources(string projectDir, string entry, List<string> sources)
{
    string full = Path.Combine(projectDir, entry);
    if (Directory.Exists(full))
    {
        foreach (var f in Directory.FindFiles(full, ".csh"))
            sources.Add(f);
        return;
    }
    if (File.Exists(full))
    {
        sources.Add(full);
        return;
    }
    return error("source '" + entry + "' does not exist (looked for '" + full + "')");
}

// The strings of an array property. 'present' tells whether the property exists.
Error<List<string>> ReadStringList(Json json, int obj, string key, string file, ref bool present)
{
    var values = List<string>.Create();
    int v = json.Get(obj, key);
    if (v < 0)
        return values;
    present = true;
    if (json.KindOf(v) != JsonKind.Array)
        return error(file + ": '" + key + "' must be an array of strings");
    foreach (var item in json.Nodes.Get(v).Items)
    {
        if (json.KindOf(item) != JsonKind.String)
            return error(file + ": '" + key + "' must be an array of strings");
        values.Add(json.Text(item));
    }
    return values;
}

// A string property; "" if it does not exist.
Error<string> ReadString(Json json, int obj, string key, string file, string fallback)
{
    int v = json.Get(obj, key);
    if (v < 0)
        return fallback;
    if (json.KindOf(v) != JsonKind.String)
        return error(file + ": '" + key + "' must be a string");
    return json.Text(v);
}

bool EndsWithAny(string s, string[] endings)
{
    foreach (var e in endings)
    {
        if (s.Length > e.Length && s.EndsWith(e))
            return true;
    }
    return false;
}

// The platform of a target triple ("windows", "macos" or "linux"); the host system for an empty triple.
string PlatformOf(string target)
{
    string lower = target.ToLower();
    if (lower.Length == 0)
    {
        if (Process.IsWindows())
            return "windows";
        return File.Exists("/System/Library/CoreServices/SystemVersion.plist") ? "macos" : "linux";
    }
    if (lower.Contains("windows") || lower.Contains("mingw"))
        return "windows";
    if (lower.Contains("apple") || lower.Contains("darwin") || lower.Contains("macos"))
        return "macos";
    return "linux";
}

// "platforms": { "windows": { "links": [...], ... }, "linux": {...}, "macos": {...} } - entries that only apply when
// building for that platform; they are added to the lists of the project.
Error<void> ReadPlatformLists(Json json, int root, string file, string platform, List<string> links, List<string> includes,
                              List<string> libraries, List<string> defines)
{
    int platforms = json.Get(root, "platforms");
    if (platforms < 0)
        return;
    if (json.KindOf(platforms) != JsonKind.Object)
        return error(file + ": 'platforms' must be an object with the keys \"windows\", \"linux\" and/or \"macos\"");
    var keys = json.Nodes.Get(platforms).Keys;
    for (var i = 0; i < keys.Count(); i += 1)
    {
        string name = keys.Get(i);
        if (name != "windows" && name != "linux" && name != "macos")
            return error(file + ": unknown platform '" + name + "' in 'platforms' (use \"windows\", \"linux\" or \"macos\")");
        int entry = json.Nodes.Get(platforms).Items.Get(i);
        if (json.KindOf(entry) != JsonKind.Object)
            return error(file + ": 'platforms." + name + "' must be an object");
        foreach (var key in json.Nodes.Get(entry).Keys)
        {
            if (key != "links" && key != "includePaths" && key != "libraryPaths" && key != "defines")
                return error(file + ": 'platforms." + name + "' may contain \"links\", \"includePaths\", \"libraryPaths\" and \"defines\", not '" + key + "'");
        }
        if (name != platform)
            continue;
        bool present = false;
        foreach (var v in try ReadStringList(json, entry, "links", file, ref present))
            links.Add(v);
        foreach (var v in try ReadStringList(json, entry, "includePaths", file, ref present))
            includes.Add(v);
        foreach (var v in try ReadStringList(json, entry, "libraryPaths", file, ref present))
            libraries.Add(v);
        foreach (var v in try ReadStringList(json, entry, "defines", file, ref present))
            defines.Add(v);
    }
    return;
}

// 'target' is the target given on the command line ("" if none): it decides which "platforms" entries apply.
Error<Project> LoadProject(string location, string target)
{
    return LoadProjectIn(location, target, List<string>.Create(), List<string>.Create());
}

// A project and its dependencies. 'chain' holds the project files (full paths) whose dependencies lead to this one (a
// project that depends on itself is an error); 'merged' the dependencies that are already a part of the program (a
// library that two projects use is merged once).
Error<Project> LoadProjectIn(string location, string target, List<string> chain, List<string> merged)
{
    string file = try FindProjectFile(location);
    string text = "";
    var read = File.ReadAllText(file);
    if (read is string content)
        text = content;
    else
        return error("cannot read '" + file + "'");
    if (text.Length >= 3 && text[0] == (char)0xEF && text[1] == (char)0xBB && text[2] == (char)0xBF)
        text = text.Substring(3);

    var json = Json.Create(text);
    var parsed = json.ParseDocument();
    int root = 0;
    if (parsed is int rootNode)
        root = rootNode;
    else
        return error(file + ": invalid JSON: " + parsed.Message);
    if (json.KindOf(root) != JsonKind.Object)
        return error(file + ": the project file must contain a JSON object");

    var p = Project { File = file, Dir = Path.GetDirectory(file), Type = "executable", Optimize = 2 };
    p.Sources = List<string>.Create();
    p.Links = List<string>.Create();
    p.LinkFiles = List<string>.Create();
    p.IncludePaths = List<string>.Create();
    p.LibraryPaths = List<string>.Create();
    p.DependencyDirs = List<string>.Create();

    string[] known = new string[] { "$schema", "name", "version", "type", "sources", "output", "optimize", "links", "target",
                                    "includePaths", "libraryPaths", "defines", "ffiApi", "platforms", "unchecked", "backend", "ndk", "debug",
                                    "dependencies", "assets" };
    var keys = json.Nodes.Get(root).Keys;
    for (var i = 0; i < keys.Count(); i += 1)
    {
        bool isKnown = false;
        foreach (var k in known)
        {
            if (k == keys.Get(i))
                isKnown = true;
        }
        if (!isKnown)
            Console.WriteErrorLine(file + ": warning: unknown key '" + keys.Get(i) + "' is ignored");
    }

    p.Name = try ReadString(json, root, "name", file, "");
    if (!ValidProjectName(p.Name))
        return error(file + ": 'name' is required and may only contain letters, digits, '_', '-' and '.'");
    p.Version = try ReadString(json, root, "version", file, "");
    p.Type = try ReadString(json, root, "type", file, "executable");
    p.Output = try ReadString(json, root, "output", file, "");
    p.Target = try ReadString(json, root, "target", file, "");
    p.Backend = try ReadString(json, root, "backend", file, "");
    p.Ndk = try ReadString(json, root, "ndk", file, "");
    if (p.Ndk.Length > 0 && !IsAbsolutePath(p.Ndk))
        p.Ndk = Path.Combine(p.Dir, p.Ndk);
    if (p.Backend.Length > 0 && p.Backend != "llvm" && p.Backend != "m68k" && p.Backend != "wasm")
        return error(file + ": 'backend' must be \"llvm\", \"m68k\" or \"wasm\", not \"" + p.Backend + "\"");
    if (p.Type != "executable" && p.Type != "object" && p.Type != "library")
        return error(file + ": 'type' must be \"executable\", \"object\" or \"library\", not \"" + p.Type + "\"");

    int opt = json.Get(root, "optimize");
    if (opt >= 0)
    {
        bool valid = json.KindOf(opt) == JsonKind.Number && json.Text(opt).Length == 1 && json.Text(opt)[0] >= '0' && json.Text(opt)[0] <= '3';
        if (!valid)
            return error(file + ": 'optimize' must be an integer from 0 to 3");
        p.Optimize = (int)json.Text(opt)[0] - 48;
        p.HasOptimize = true;
    }

    int uncheckedNode = json.Get(root, "unchecked");
    if (uncheckedNode >= 0)
    {
        if (json.KindOf(uncheckedNode) != JsonKind.Bool)
            return error(file + ": 'unchecked' must be true or false");
        p.Unchecked = json.Nodes.Get(uncheckedNode).Flag;
    }

    int debugNode = json.Get(root, "debug");
    if (debugNode >= 0)
    {
        if (json.KindOf(debugNode) != JsonKind.Bool)
            return error(file + ": 'debug' must be true or false");
        p.Debug = json.Nodes.Get(debugNode).Flag;
    }

    bool present = false;
    var linkEntries = try ReadStringList(json, root, "links", file, ref present);
    var includeEntries = try ReadStringList(json, root, "includePaths", file, ref present);
    var libraryEntries = try ReadStringList(json, root, "libraryPaths", file, ref present);
    p.Defines = try ReadStringList(json, root, "defines", file, ref present);
    p.ApiPaths = try ReadStringList(json, root, "ffiApi", file, ref present);
    try ReadPlatformLists(json, root, file, PlatformOf(target.Length > 0 ? target : p.Target), linkEntries, includeEntries,
                          libraryEntries, p.Defines);
    bool sourcesPresent = false;
    var sourceEntries = try ReadStringList(json, root, "sources", file, ref sourcesPresent);
    if (!sourcesPresent)
        sourceEntries.Add("src");

    foreach (var entry in sourceEntries)
        try AddSources(p.Dir, entry, p.Sources);
    p.Sources.Sort();
    // remove duplicates (the list is sorted)
    var unique = List<string>.Create();
    foreach (var s in p.Sources)
    {
        if (unique.Count() == 0 || unique.Get(unique.Count() - 1) != s)
            unique.Add(s);
    }
    p.Sources = unique;
    if (p.Sources.Count() == 0)
        return error(file + ": no .csh source files found");

    // "links" entries that name a file (or contain a path) are passed to the linker as files, everything else is a
    // library name (-l<name>).
    string[] fileEndings = new string[] { ".a", ".o", ".obj", ".lib", ".so", ".dylib", ".dll" };
    foreach (var pth in includeEntries)
        p.IncludePaths.Add(InProject(p.Dir, pth));
    foreach (var pth in libraryEntries)
        p.LibraryPaths.Add(InProject(p.Dir, pth));
    foreach (var l in linkEntries)
    {
        bool isFile = l.IndexOf('/') >= 0 || l.IndexOf('\\') >= 0 || EndsWithAny(l, fileEndings);
        if (isFile)
            p.LinkFiles.Add(InProject(p.Dir, l));
        else
            p.Links.Add(l);
    }

    // the files a program reads at run time, for 'publish': inside of the project, where they are found at the same
    // relative paths in the browser
    present = false;
    p.Assets = try ReadStringList(json, root, "assets", file, ref present);
    foreach (var asset in p.Assets)
    {
        string normal = asset.Replace("\\", "/");
        if (IsAbsolutePath(asset) || normal == ".." || normal.StartsWith("../") || normal.Contains("/../") || normal.EndsWith("/.."))
            return error(file + ": the asset '" + asset + "' is not inside of the project (\"assets\" are relative paths in it)");
    }

    present = false;
    var dependencyEntries = try ReadStringList(json, root, "dependencies", file, ref present);
    if (dependencyEntries.Count() > 0)
    {
        string self = Path.GetFullPath(file);
        chain.Add(self);
        foreach (var entry in dependencyEntries)
        {
            string where = Path.GetFullPath(InProject(p.Dir, entry));
            string depFile = Directory.Exists(where) ? Path.Combine(where, "cshift.json") : where;
            if (!File.Exists(depFile))
                return error(file + ": the dependency '" + entry + "' does not exist (there is no " + depFile + ")");
            if (chain.Contains(depFile))
            {
                // the projects of the cycle, by their folders
                string cwd = Directory.GetCurrentDirectory();
                var cycle = List<string>.Create();
                bool inCycle = false;
                foreach (var f in chain)
                {
                    inCycle = inCycle || f == depFile;
                    if (inCycle)
                        cycle.Add(Path.GetRelativePath(cwd, Path.GetDirectory(f)));
                }
                cycle.Add(Path.GetRelativePath(cwd, Path.GetDirectory(depFile)));
                return error(file + ": the dependencies form a cycle: " + string.Join(" -> ", cycle.ToArray()));
            }
            if (merged.Contains(depFile))
                continue;
            merged.Add(depFile);
            var loaded = LoadProjectIn(depFile, target.Length > 0 ? target : p.Target, chain, merged);
            if (loaded is Project dep)
            {
                if (dep.Type != "library")
                    return error(file + ": the dependency '" + entry + "' is not a library (its cshift.json needs \"type\": \"library\")");
                p.DependencyDirs.Add(dep.Dir.Length > 0 ? dep.Dir : ".");
                AppendAll(p.DependencyDirs, dep.DependencyDirs);
                foreach (var s in dep.Sources)
                {
                    if (!p.Sources.Contains(s))
                        p.Sources.Add(s);
                }
                AppendAll(p.Links, dep.Links);
                AppendAll(p.LinkFiles, dep.LinkFiles);
                AppendAll(p.IncludePaths, dep.IncludePaths);
                AppendAll(p.LibraryPaths, dep.LibraryPaths);
                AppendAll(p.Defines, dep.Defines);
                AppendAll(p.ApiPaths, dep.ApiPaths);
            }
            else
                return error(loaded.Message);
        }
        chain.RemoveAt(chain.Count() - 1);
    }

    if (p.Output.Length == 0)
        p.Output = "bin/" + p.Name;
    p.Output = Path.Combine(p.Dir, p.Output);
    return p;
}

void AppendAll(List<string> to, List<string> values)
{
    foreach (var v in values)
        to.Add(v);
}

bool IsAbsolutePath(string p)
{
    return p.Length > 0 && (p[0] == '/' || p[0] == '\\' || (p.Length > 1 && p[1] == ':'));
}

string InProject(string dir, string p)
{
    if (IsAbsolutePath(p) || dir.Length == 0)
        return p;
    return Path.Combine(dir, p);
}

// cshc new <path>: a new project directory with cshift.json and src/main.csh.
Error<void> CreateProject(string projectPath)
{
    if (Directory.Exists(projectPath) || File.Exists(projectPath))
        return error("'" + projectPath + "' already exists");
    string trimmed = projectPath.Replace("\\", "/");
    while (trimmed.Length > 1 && trimmed[trimmed.Length - 1] == '/')
        trimmed = trimmed.Substring(0, trimmed.Length - 1);
    string name = Path.GetFileName(trimmed);
    if (!ValidProjectName(name))
        return error("invalid project name '" + name + "' (letters, digits, '_', '-' and '.' are allowed)");

    string src = Path.Combine(projectPath, "src");
    if (!Directory.Create(src))
        return error("cannot create '" + src + "'");

    string json = "{\n\t\"name\": \"" + name + "\",\n\t\"version\": \"0.1.0\",\n\t\"type\": \"executable\",\n" +
                  "\t\"sources\": [\"src\"],\n\t\"output\": \"bin/" + name + "\",\n\t\"optimize\": 2,\n\t\"links\": []\n}\n";
    string main = "int Main()\n{\n    Console.WriteLine(\"Hello, World!\");\n    return 0;\n}\n";
    try File.WriteAllText(Path.Combine(projectPath, "cshift.json"), json);
    try File.WriteAllText(Path.Combine(src, "main.csh"), main);
    try File.WriteAllText(Path.Combine(projectPath, ".gitignore"), "bin/\nobj/\n");
    return;
}
