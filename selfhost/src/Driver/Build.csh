// The command line of cshc: single files and projects.
//
//     cshc [options] file.csh [file2.csh ...]     compile single files
//     cshc build [project] [options]              build a project (cshift.json)
//     cshc run   [project] [options]              build and run a project
//     cshc publish [project | files] [options]    the program as one HTML file for the browser (Publish.csh)
//     cshc serve [project | files] [options]      a server for the page that builds it again on changes (Serve.csh)
//     cshc new   <directory>                      create a new project
//     cshc check [project | files] [options]      report the errors, generate nothing
//     cshc query --at <file> <line> <col> [...]   the name at a position, as JSON (for the VS Code extension)
//     cshc doc [project | files]                  the documentation of the doc comments, as JSON (Doc.csh)
//
// The code generator writes LLVM IR as text; clang optimizes it, generates the object code and links.

namespace CShift.Driver;

using System;
using CShift.Syntax;
using CShift.CodeGen;
using CShift.Check;
using CShift.M68k;
using CShift.Wasm;
using CShift.Emit;

struct BuildOptions
{
    List<string> Inputs;
    string Output;
    string Target;
    string Cc;
    string Stdlib;
    string ProjectDir;
    List<FfiImport> Imports;    // "using X from header" declarations found in the sources
    int Optimize;
    bool OptimizeGiven;
    bool ObjectOnly;
    bool EmitLlvm;
    bool EmitAsm;               // --emit-asm: the assembly of the m68k backend
    string Backend;             // --backend: "llvm", "m68k" or "wasm" ("" = the project's, else the target's default)
    string Ndk;                 // --ndk: the AmigaOS NDK (SFD files for "using X from "lib.sfd";")
    bool Run;
    bool Verbose;
    bool ArcStats;
    bool Debug;              // -g: debug information
    bool Unchecked;             // --unchecked: integer overflow wraps instead of a panic
    bool Checked;               // --checked: overflow panics even if the project file says "unchecked": true
    List<string> Libs;          // -l<name>
    List<string> LibFiles;      // .a/.o/.lib files for the linker
    List<string> LibPaths;      // -L<dir>
    List<string> IncludePaths;  // -I<dir>
    List<string> Defines;       // -D<name>
    List<string> ApiPaths;      // --ffi-api=<text>
    bool FromProject;
    string ProjectName;
    string Mode;                // "" (build), "check" or "query": the front end only
    string AtFile;              // query: the position
    int AtLine;
    int AtCol;
    bool References;            // query: also every place where the name is written
    bool Members;               // query: what can follow 'name.' (completion)
    bool RequireDocs;           // doc: every public declaration needs a doc comment
    string OutlineFile;         // query: the declarations of this file instead of a position
    Dictionary<string, string> Overlays; // the full path of a source -> a file with its current (unsaved) text
    int ServePort;              // serve: --port (0: the first free one from 8080 on)
    string ServeHost;           // serve: --host (default 127.0.0.1)
    bool ServeOpen;             // serve: --open, the page in the browser

    static BuildOptions Create()
    {
        var o = BuildOptions { Output = "", Target = "", Backend = "", Ndk = "", Cc = "", Stdlib = "", ProjectDir = "", Optimize = 2, ProjectName = "", Mode = "",
                               AtFile = "", OutlineFile = "", ServeHost = "" };
        o.Overlays = Dictionary<string, string>.Create();
        o.Imports = List<FfiImport>.Create();
        o.Inputs = List<string>.Create();
        o.Libs = List<string>.Create();
        o.LibFiles = List<string>.Create();
        o.LibPaths = List<string>.Create();
        o.IncludePaths = List<string>.Create();
        o.Defines = List<string>.Create();
        o.ApiPaths = List<string>.Create();
        return o;
    }
}

// usage.txt, embedded when cshc is compiled
const string UsageText = embed("usage.txt");

void PrintUsage()
{
    Console.WriteError(UsageText);
}

bool IsLinkerInput(string a)
{
    string[] endings = new string[] { ".a", ".o", ".obj", ".lib", ".so", ".dylib" };
    return EndsWithAny(a, endings);
}

// Reads the options from args[first..]. Returns false after printing an error.
bool ParseOptions(string[] args, int first, ref BuildOptions o)
{
    for (var i = first; i < args.Length; i += 1)
    {
        string a = args[i];
        if (a == "-o" && i + 1 < args.Length)
        {
            i += 1;
            o.Output = args[i];
        }
        else if (a == "--cc" && i + 1 < args.Length)
        {
            i += 1;
            o.Cc = args[i];
        }
        else if (a == "--stdlib" && i + 1 < args.Length)
        {
            i += 1;
            o.Stdlib = args[i];
        }
        else if (a == "--target" && i + 1 < args.Length)
        {
            i += 1;
            o.Target = args[i];
        }
        else if (a == "--port" && i + 1 < args.Length)
        {
            i += 1;
            o.ServePort = (int)ParseNumber(args[i]);
            if (o.ServePort <= 0 || o.ServePort > 65535)
            {
                Console.WriteErrorLine("error: --port needs a number from 1 to 65535, not '" + args[i] + "'");
                return false;
            }
        }
        else if (a == "--host" && i + 1 < args.Length)
        {
            i += 1;
            o.ServeHost = args[i];
        }
        else if (a == "--open")
            o.ServeOpen = true;
        else if (a == "--no-stdlib")
            o.Stdlib = "-";
        else if (a == "--at" && i + 3 < args.Length)
        {
            o.AtFile = args[i + 1];
            o.AtLine = (int)ParseNumber(args[i + 2]);
            o.AtCol = (int)ParseNumber(args[i + 3]);
            i += 3;
        }
        else if (a == "--references")
            o.References = true;
        else if (a == "--members")
            o.Members = true;
        else if (a == "--require-docs")
            o.RequireDocs = true;
        else if (a == "--outline" && i + 1 < args.Length)
        {
            o.OutlineFile = args[i + 1];
            i += 1;
        }
        else if (a == "--overlay" && i + 2 < args.Length)
        {
            o.Overlays.Set(SamePath(args[i + 1]), args[i + 2]);
            i += 2;
        }
        else if (a == "-c")
            o.ObjectOnly = true;
        else if (a == "--emit-llvm")
            o.EmitLlvm = true;
        else if (a == "--emit-asm")
            o.EmitAsm = true;
        else if (a == "--backend" && i + 1 < args.Length)
        {
            i += 1;
            o.Backend = args[i];
            if (o.Backend != "llvm" && o.Backend != "m68k" && o.Backend != "wasm")
            {
                Console.WriteErrorLine("error: unknown backend '" + o.Backend + "' (llvm, m68k or wasm)");
                return false;
            }
        }
        else if (a == "--ndk" && i + 1 < args.Length)
        {
            i += 1;
            o.Ndk = args[i];
        }
        else if (a == "--arc-stats")
            o.ArcStats = true;
        else if (a == "-g")
            o.Debug = true;
        else if (a == "--unchecked")
            o.Unchecked = true;
        else if (a == "--checked")
            o.Checked = true;
        else if (a == "--run")
            o.Run = true;
        else if (a == "-v")
            o.Verbose = true;
        else if (a == "-O0" || a == "-O1" || a == "-O2" || a == "-O3")
        {
            o.Optimize = (int)a[2] - 48;
            o.OptimizeGiven = true;
        }
        else if (a.StartsWith("-l") && a.Length > 2)
            o.Libs.Add(a.Substring(2));
        else if (a.StartsWith("-L") && a.Length > 2)
            o.LibPaths.Add(a.Substring(2));
        else if (a.StartsWith("-I") && a.Length > 2)
            o.IncludePaths.Add(a.Substring(2));
        else if (a.StartsWith("-D") && a.Length > 2)
            o.Defines.Add(a.Substring(2));
        else if (a.StartsWith("--ffi-api="))
            o.ApiPaths.Add(a.Substring(10));
        else if (a.Length > 0 && a[0] == '-')
        {
            Console.WriteErrorLine("error: unknown option '" + a + "' (or a value is missing)");
            return false;
        }
        else if (IsLinkerInput(a))
            o.LibFiles.Add(a);
        else
            o.Inputs.Add(a);
    }
    if (o.Checked && o.Unchecked)
    {
        Console.WriteErrorLine("error: --checked and --unchecked cannot be used together");
        return false;
    }
    return true;
}

// The entry point of the driver: returns the exit code.
int Cshc(string[] args)
{
    if (args.Length == 0 || args[0] == "-h" || args[0] == "--help")
    {
        PrintUsage();
        return args.Length == 0 ? 2 : 0;
    }
    if (args[0] == "--version")
    {
        Console.WriteLine("cshiftc " + CshcVersion() + " (self-hosted)");
        return 0;
    }
    if (args[0] == "--clear-cache")
        return ClearToolchainCache();

    var o = BuildOptions.Create();
    string command = "compile";
    int first = 0;
    if (args[0] == "build" || args[0] == "run" || args[0] == "new" || args[0] == "check" || args[0] == "query" ||
        args[0] == "doc" || args[0] == "publish" || args[0] == "serve")
    {
        command = args[0];
        first = 1;
    }
    if (!ParseOptions(args, first, ref o))
        return 2;

    if (command == "new")
    {
        if (o.Inputs.Count() != 1)
        {
            PrintUsage();
            return 2;
        }
        string dir = o.Inputs.Get(0);
        var created = CreateProject(dir);
        if (created is error createdError)
        {
            Console.WriteErrorLine("error: " + createdError.Message);
            return 1;
        }
        Console.WriteLine("Created project '" + dir + "'\n  cd " + dir + "\n  " + CompilerName() + " run");
        return 0;
    }

    if (command == "doc")
    {
        // the standard library, or files or a project like 'check'
        o.Mode = command;
        if (o.Inputs.Count() > 0 && !o.Inputs.Get(0).EndsWith(".csh"))
        {
            var found = LoadProject(o.Inputs.Get(0), o.Target);
            if (found is Project p)
            {
                o.FromProject = true;
                o.ProjectDir = p.Dir;
                o.Inputs = p.Sources;
                if (o.Target.Length == 0)
                    o.Target = p.Target;
                if (o.Backend.Length == 0)
                    o.Backend = p.Backend;
            }
            else
            {
                Console.WriteErrorLine("error: " + found.Message);
                return 1;
            }
        }
        return Build(o);
    }

    if (command == "check" || command == "query")
    {
        o.Mode = command;
        if (command == "query" && o.AtFile.Length == 0 && o.OutlineFile.Length == 0)
        {
            Console.WriteErrorLine("error: 'query' needs --at <file> <line> <col> or --outline <file>");
            return 2;
        }
        if (o.AtFile.Length == 0)
            o.AtFile = o.OutlineFile;
        // single files, or a project like 'build' (the project of the queried file if none is named)
        bool files = o.Inputs.Count() > 0 && o.Inputs.Get(0).EndsWith(".csh");
        if (!files)
        {
            string location = o.Inputs.Count() > 0 ? o.Inputs.Get(0) : (command == "query" ? ProjectAbove(o.AtFile) : "");
            var found = LoadProject(location, o.Target);
            if (found is Project p)
            {
                o.FromProject = true;
                o.ProjectDir = p.Dir;
                o.Inputs = p.Sources;
                o.Unchecked = o.Unchecked || (p.Unchecked && !o.Checked);
                if (o.Target.Length == 0)
                    o.Target = p.Target;
                if (o.Backend.Length == 0)
                    o.Backend = p.Backend;
                if (o.Ndk.Length == 0)
                    o.Ndk = p.Ndk;
                foreach (var l in p.IncludePaths)
                    o.IncludePaths.Insert(0, l);
                foreach (var l in p.Defines)
                    o.Defines.Insert(0, l);
                foreach (var l in p.ApiPaths)
                    o.ApiPaths.Insert(0, l);
            }
            else if (command == "query" && o.Inputs.Count() == 0)
                o.Inputs.Add(o.AtFile); // a file without a project
            else
            {
                Console.WriteErrorLine("error: " + found.Message);
                return 1;
            }
        }
        return Build(o);
    }

    if (command == "publish")
        return Publish(o);
    if (command == "serve")
        return Serve(args, o);

    if (command == "build" || command == "run")
    {
        string location = o.Inputs.Count() > 0 ? o.Inputs.Get(0) : "";
        var loaded = LoadProject(location, o.Target);
        if (loaded is Project project)
        {
            ApplyProject(ref o, project);
            if (project.Type == "object")
                o.ObjectOnly = true;
            if (command == "run")
                o.Run = true;
            if (project.Type == "library")
            {
                // a library is compiled as a part of the programs that use it ("dependencies"): building it alone
                // checks it
                if (command == "run")
                {
                    Console.WriteErrorLine("error: '" + project.Name + "' is a library (\"type\": \"library\"): it is run as a part of " +
                                           "the projects that name it in \"dependencies\"");
                    return 1;
                }
                o.Mode = "check";
                int checkedResult = Build(o);
                if (checkedResult == 0)
                    Console.WriteLine("Checked library '" + project.Name + "' (it is compiled into the projects that name it in \"dependencies\")");
                return checkedResult;
            }
        }
        else
        {
            Console.WriteErrorLine("error: " + loaded.Message);
            return 1;
        }
    }

    if (o.Inputs.Count() == 0)
    {
        PrintUsage();
        return 2;
    }
    return Build(o);
}

// The settings of a project file for build, run and publish; the options of the command line win.
void ApplyProject(ref BuildOptions o, Project project)
{
    o.FromProject = true;
    o.ProjectName = project.Name;
    o.ProjectDir = project.Dir;
    o.Inputs = project.Sources;
    o.Unchecked = o.Unchecked || (project.Unchecked && !o.Checked);
    o.Debug = o.Debug || project.Debug;
    if (o.Output.Length == 0)
        o.Output = project.Output;
    if (!o.OptimizeGiven && project.HasOptimize)
        o.Optimize = project.Optimize;
    if (o.Target.Length == 0)
        o.Target = project.Target;
    if (o.Backend.Length == 0)
        o.Backend = project.Backend;
    if (o.Ndk.Length == 0)
        o.Ndk = project.Ndk;
    foreach (var l in project.Links)
        o.Libs.Insert(0, l);
    foreach (var l in project.LinkFiles)
        o.LibFiles.Insert(0, l);
    foreach (var l in project.LibraryPaths)
        o.LibPaths.Insert(0, l);
    foreach (var l in project.IncludePaths)
        o.IncludePaths.Insert(0, l);
    foreach (var l in project.Defines)
        o.Defines.Insert(0, l);
    foreach (var l in project.ApiPaths)
        o.ApiPaths.Insert(0, l);
}

// The version: selfhost/version/version.txt, read when cshc is compiled (the release workflow writes it).
string CshcVersion()
{
    const ReadOnlySlice<string> Texts = embed("../../version/version*.txt");
    return Texts.Length > 0 ? Texts[0].Trim().ToString() : "dev";
}

// The C compiler that is used as linker driver, to compile generated C code and to find libclang: --cc, then
// CSHIFT_CC, then the toolchain that comes with cshc (the folder 'toolchain' next to it, or the one a standalone
// build carries inside itself), then clang, cc or gcc from PATH, then the usual MSYS2 folders on Windows.
string LocateClang(string cc, bool windows)
{
    if (cc.Length > 0)
    {
        string found = FindProgram(cc, windows);
        return found.Length > 0 ? found : cc;
    }
    var fromEnv = Process.GetEnv("CSHIFT_CC");
    if (fromEnv is string configured)
    {
        if (configured.Length > 0)
        {
            string found = FindProgram(configured, windows);
            return found.Length > 0 ? found : configured;
        }
    }
    string bundled = BundledClang(windows);
    if (bundled.Length > 0)
        return bundled;
    foreach (var name in new string[] { "clang", "cc", "gcc" })
    {
        string found = FindProgram(name, windows);
        if (found.Length > 0)
            return found;
    }
    if (windows)
    {
        var root = Process.GetEnv("MSYS2_ROOT");
        if (root is string msys)
        {
            if (File.Exists(msys + "/clang64/bin/clang.exe"))
                return msys + "/clang64/bin/clang.exe";
        }
        if (File.Exists("C:/msys64/clang64/bin/clang.exe"))
            return "C:/msys64/clang64/bin/clang.exe";
    }
    return "";
}

// The path of a program: as it is if it contains a directory, otherwise searched in PATH ("" if not found).
string FindProgram(string name, bool windows)
{
    string exe = windows && !name.ToLower().EndsWith(".exe") ? name + ".exe" : name;
    if (name.Contains('/') || name.Contains('\\'))
        return File.Exists(exe) ? exe : (File.Exists(name) ? name : "");
    var path = Process.GetEnv("PATH");
    if (path is string dirs)
    {
        foreach (var dir in dirs.Split(windows ? ';' : ':'))
        {
            if (dir.Length == 0)
                continue;
            string candidate = Path.Combine(dir.ToString(), exe);
            if (File.Exists(candidate))
                return Path.Normalize(candidate);
        }
    }
    return "";
}

// The release archives contain a toolchain (clang, lld, libclang, C libraries) in the folder 'toolchain' next to the
// compiler; it is used before anything in PATH so that the versions match. A standalone build carries the same
// toolchain appended to its own file (packaging/make-standalone.sh) and extracts it into a cache directory the first
// time it is needed.
string BundledClang(bool windows)
{
    string self = Host.ExecutablePath();
    if (self.Length == 0)
        return "";
    string clangName = windows ? "clang.exe" : "clang";
    string candidate = Path.Combine(Path.Combine(Path.Combine(Path.GetDirectory(Path.Normalize(self)), "toolchain"), "bin"), clangName);
    if (File.Exists(candidate))
        return candidate;

    int64 offset = 0;
    int64 size = 0;
    if (Host.EmbeddedToolchain(self, ref offset, ref size) == 0)
        return "";
    string cacheDir = ToolchainCacheDir(windows);
    if (cacheDir.Length == 0)
        return "";
    string cached = Path.Combine(Path.Combine(Path.Combine(cacheDir, "toolchain"), "bin"), clangName);
    if (File.Exists(cached))
        return cached;
    // extracted with the system 'tar' (part of Windows since 10 1803 and of every Linux/macOS)
    if (!Directory.Create(cacheDir))
        return "";
    string archive = Path.Combine(cacheDir, "toolchain.tar.gz");
    if (Host.CopyFilePart(self, offset, size, archive) == 0)
        return "";
    Process.Run(TarCommand(windows) + " xzf \"" + NativePath(archive, windows) + "\" -C \"" + NativePath(cacheDir, windows) + "\"");
    File.Delete(archive);
    return File.Exists(cached) ? cached : "";
}

// The system 'tar'. On Windows that is %SystemRoot%\System32\tar.exe (bsdtar): a GNU tar found first in PATH (Git
// for Windows, MSYS2) would read "D:\..." as a remote host.
string TarCommand(bool windows)
{
    if (windows)
    {
        var root = Process.GetEnv("SystemRoot");
        if (root is string r && r.Length > 0)
        {
            string tar = r + "\\System32\\tar.exe";
            if (File.Exists(tar))
                return "\"" + tar + "\"";
        }
    }
    return "tar";
}

// A per-user, per-version cache directory for the extracted toolchain.
string ToolchainCacheDir(bool windows)
{
    string root = ToolchainCacheRoot(windows);
    if (root.Length == 0)
        return "";
    return Path.Combine(root, "toolchain-" + CshcVersion());
}

// --clear-cache: the cache directory of the standalone builds goes (every version's toolchain; it is unpacked again
// the next time a standalone cshiftc needs it).
int ClearToolchainCache()
{
    bool windows = Process.IsWindows();
    string root = ToolchainCacheRoot(windows);
    if (root.Length == 0)
    {
        Console.WriteErrorLine("error: no cache directory (neither LOCALAPPDATA nor XDG_CACHE_HOME/HOME is set)");
        return 1;
    }
    if (!Directory.Exists(root))
    {
        Console.WriteLine("nothing to clear (" + root + " does not exist)");
        return 0;
    }
    string path = NativePath(root, windows);
    if (windows)
        Process.Run("rmdir /s /q \"" + path + "\"");
    else
        Process.Run("rm -rf \"" + path + "\"");
    if (Directory.Exists(root))
    {
        Console.WriteErrorLine("error: could not delete " + root);
        return 1;
    }
    Console.WriteLine("deleted " + root);
    return 0;
}

// The per-user directory that holds the toolchains of all versions (<cache>/cshift).
string ToolchainCacheRoot(bool windows)
{
    string baseDir = "";
    if (windows)
    {
        var local = Process.GetEnv("LOCALAPPDATA");
        if (local is string l)
            baseDir = l;
    }
    else
    {
        var xdg = Process.GetEnv("XDG_CACHE_HOME");
        var home = Process.GetEnv("HOME");
        if (xdg is string x && x.Length > 0)
            baseDir = x;
        else if (home is string h && h.Length > 0)
            baseDir = h + "/.cache";
    }
    if (baseDir.Length == 0)
        return "";
    return Path.Combine(Path.Normalize(baseDir), "cshift");
}

void EnsureParentDirectory(string file)
{
    string dir = Path.GetDirectory(file);
    if (dir.Length > 0 && !Directory.Exists(dir))
        Directory.Create(dir);
}

string NativePath(string path, bool windows)
{
    return windows ? path.Replace("/", "\\") : path;
}

// Compiles the inputs of the options. Returns the exit code.
int Build(BuildOptions o)
{
    bool windows = Process.IsWindows();
    if (o.Target.Length > 0)
    {
        string lower = o.Target.ToLower();
        windows = lower.Contains("windows") || lower.Contains("mingw");
    }

    // ---- parse ----
    var diag = Diagnostics.Create();
    var tree = Ast.Create();
    if (o.Backend.Length == 0)
        o.Backend = TargetInfo.DefaultBackend(o.Target);
    if (o.Backend == "m68k" && o.Target.Length == 0)
        o.Target = "m68k-amigaos";
    // the AmigaOS NDK: its SFD files (Ffi.csh) and C headers
    if (o.Ndk.Length == 0 && Process.GetEnv("CSHIFT_NDK") is string envNdk)
        o.Ndk = envNdk;
    if (o.Ndk.Length > 0 && o.Target.Contains("amigaos"))
        o.IncludePaths.Add(Path.Combine(o.Ndk, "Include_H"));
    if (o.Backend == "m68k" && !o.Target.ToLower().StartsWith("m68k"))
    {
        Console.WriteErrorLine("error: the m68k backend generates code for m68k targets, not '" + o.Target + "'");
        return 1;
    }
    if (o.Backend == "wasm" && o.Target.Length == 0)
        o.Target = "wasm32-wasi";
    if (o.Backend == "wasm" && !o.Target.ToLower().StartsWith("wasm32"))
    {
        Console.WriteErrorLine("error: the wasm backend generates code for wasm32 targets, not '" + o.Target + "'");
        return 1;
    }
    // the backends of CShift read the IR themselves and have no use for debug information
    bool ownBackend = o.Backend == "m68k" || o.Backend == "wasm";
    var cg = Compiler.Create(tree, diag, windows, o.Target, o.Backend);
    cg.St[0].ArcStats = o.ArcStats;
    cg.Ir.Debug = o.Debug && !ownBackend;
    if (o.Debug && ownBackend)
        Console.WriteErrorLine("warning: -g has no effect with the " + o.Backend + " backend");
    cg.St[0].Unchecked = o.Unchecked;
    if (o.FromProject)
        cg.St[0].ProjectDir = o.ProjectDir.Length > 0 ? o.ProjectDir : ".";

    // The standard library (stdlib/*.csh) is parsed as a prelude: its functions are only compiled when they are used.
    // Without --stdlib the copy that is embedded in cshc is used (src/Driver/EmbeddedStdlib.csh).
    if (o.Stdlib.Length == 0)
    {
        for (var i = 0; i < EmbeddedStdlibNames.Length; i += 1)
            AddSourceText(cg, diag, tree, "<stdlib>/" + EmbeddedStdlibNames[i], EmbeddedStdlibTexts[i], true, o.Imports);
        if (ownBackend)
        {
            for (var i = 0; i < EmbeddedM68kNames.Length; i += 1)
                AddSourceText(cg, diag, tree, "<stdlib>/m68k/" + EmbeddedM68kNames[i], EmbeddedM68kTexts[i], true, o.Imports);
        }
        if (HasOwnLibc(o))
        {
            for (var i = 0; i < EmbeddedLibcNames.Length; i += 1)
                AddSourceText(cg, diag, tree, "<stdlib>/libc/" + EmbeddedLibcNames[i], EmbeddedLibcTexts[i], true, o.Imports);
        }
        if (o.Backend == "m68k" && o.Target.Contains("amigaos"))
        {
            for (var i = 0; i < EmbeddedAmigaNames.Length; i += 1)
                AddSourceText(cg, diag, tree, "<stdlib>/amiga/" + EmbeddedAmigaNames[i], EmbeddedAmigaTexts[i], true, o.Imports);
        }
        if (o.Backend == "wasm")
        {
            for (var i = 0; i < EmbeddedWasmNames.Length; i += 1)
                AddSourceText(cg, diag, tree, "<stdlib>/wasm/" + EmbeddedWasmNames[i], EmbeddedWasmTexts[i], true, o.Imports);
        }
        foreach (var layer in OsLayers(o.Target, o.Backend, windows).ToArray())
        {
            var names = layer == "windows" ? EmbeddedOsWindowsNames : layer == "posix" ? EmbeddedOsPosixNames :
                        layer == "posix-64" ? EmbeddedOsPosix64Names : layer == "posix-32" ? EmbeddedOsPosix32Names :
                        layer == "wasi" ? EmbeddedOsWasiNames : EmbeddedOsPosixM68kNames;
            var texts = layer == "windows" ? EmbeddedOsWindowsTexts : layer == "posix" ? EmbeddedOsPosixTexts :
                        layer == "posix-64" ? EmbeddedOsPosix64Texts : layer == "posix-32" ? EmbeddedOsPosix32Texts :
                        layer == "wasi" ? EmbeddedOsWasiTexts : EmbeddedOsPosixM68kTexts;
            for (var i = 0; i < names.Length; i += 1)
                AddSourceText(cg, diag, tree, "<stdlib>/os/" + layer + "/" + names[i], texts[i], true, o.Imports);
        }
        cg.St[0].StdlibLoaded = EmbeddedStdlibNames.Length > 0;
    }
    else if (o.Stdlib != "-")
    {
        var libFiles = Directory.FindFiles(o.Stdlib, ".csh");
        foreach (var libFile in libFiles)
        {
            // the runtime of a backend (stdlib/m68k/) only belongs to programs for that backend
            // the declarations of the built-in types are only for the documentation (LoadBuiltinDocs)
            if (libFile.Contains("/builtin/"))
                continue;
            if (libFile.Contains("/m68k/") && !ownBackend)
                continue;
            if (libFile.Contains("/libc/") && !HasOwnLibc(o))
                continue;
            if (libFile.Contains("/amiga/") && !(o.Backend == "m68k" && o.Target.Contains("amigaos")))
                continue;
            if (libFile.Contains("/wasm/") && o.Backend != "wasm")
                continue;
            int osAt = Path.Normalize(libFile).IndexOf("/os/");
            if (osAt >= 0 && !OsLayers(o.Target, o.Backend, windows).Contains(Path.GetDirectory(libFile.Substring(osAt + 4).ToString())))
                continue;
            if (!AddSource(cg, diag, tree, libFile, true, o.Imports))
                return 1;
        }
        cg.St[0].StdlibLoaded = libFiles.Count() > 0;
    }
    foreach (var path in o.Inputs)
    {
        // the text in the editor, if it is not saved (query/check from the VS Code extension)
        var overlay = o.Overlays.TryGet(SamePath(path));
        if (overlay is string overlayFile)
        {
            var text = ReadSource(overlayFile);
            if (text is string overlayText)
            {
                AddSourceText(cg, diag, tree, path, overlayText, false, o.Imports);
                continue;
            }
            return 1;
        }
        if (!AddSource(cg, diag, tree, path, false, o.Imports))
            return 1;
    }
    cg.St[0].FrontEndOnly = o.Mode.Length > 0;
    cg.St[0].Indexing = o.Mode == "query";
    // after a syntax error the tree is not complete; errors of the declarations (a name defined twice) are reported
    // together with the others (docs/semantic-pass.md)
    if (cg.St[0].SyntaxErrors > 0)
    {
        if (o.Mode == "query")
            Console.WriteLine("{}");
        return 1;
    }

    if (o.Mode == "doc")
    {
        bool stdlibDoc = o.Inputs.Count() == 0;
        var builtins = stdlibDoc ? LoadBuiltinDocs(o, diag, tree) : List<CompilationUnit>.Create();
        string json = DocJson(cg, stdlibDoc, o.RequireDocs, builtins);
        if (diag.HasErrors())
            return 1;
        if (o.Output.Length > 0)
            return WriteOutput(o.Output, json);
        Console.Write(json);
        return 0;
    }

    // ---- FFI: C headers imported with "using Name from "header.h";" ----
    var shimSources = List<string>.Create();
    var importedNames = Dictionary<string, string>.Create();
    foreach (var imp in o.Imports)
    {
        var seen = importedNames.TryGet(imp.Name);
        if (seen is string seenHeader)
        {
            if (seenHeader != imp.Header)
            {
                diag.ReportAt(imp.Loc, "namespace '" + imp.Name + "' is already imported from \"" + seenHeader + "\"");
                return 1;
            }
            continue;
        }
        importedNames.Set(imp.Name, imp.Header);
        string cacheBase = (o.FromProject && o.ProjectDir.Length > 0) ? o.ProjectDir : Path.GetDirectory(imp.SourcePath);
        string cacheDir = Path.Combine(cacheBase.Length > 0 ? cacheBase : ".", "obj/ffi");
        var prepared = PrepareFfi(imp, o, cacheDir);
        if (prepared is FfiFiles files)
        {
            var headerLoc = SourceLoc { };
            var loaded = LoadFfiUnit(files.FfiPath, imp.Name, diag, tree, ref headerLoc);
            if (loaded is CompilationUnit ffiUnit)
            {
                AddUnit(cg, ffiUnit);
                cg.Imported.Set(imp.Name, ImportedNamespace { Header = imp.Header, Loc = headerLoc });
            }
            else
            {
                diag.ReportAt(imp.Loc, loaded.Message);
                return 1;
            }
            foreach (var shim in files.Shims)
                shimSources.Add(shim);
        }
        else
        {
            diag.ReportAt(imp.Loc, "cannot import \"" + imp.Header + "\": " + prepared.Message);
            return 1;
        }
    }

    string triple = o.Target;
    string ir = CompileProgram(cg, triple);
    if (o.Mode == "check")
        return diag.HasErrors() ? 1 : 0;
    if (o.Mode == "query")
    {
        Console.WriteLine(QueryAnswer(cg, diag, o, tree));
        return 0;
    }

    // ---- output files ----
    string first = o.Inputs.Get(0);
    string baseName = o.Output.Length > 0 ? o.Output : StemOf(first);
    string objExt = windows ? ".obj" : ".o";

    if (o.EmitLlvm)
    {
        string llPath = o.Output.Length == 0 ? baseName + ".ll" : (o.FromProject ? o.Output + ".ll" : o.Output);
        EnsureParentDirectory(llPath);
        var wrote = File.WriteAllText(llPath, ir);
        if (wrote is error wroteError)
        {
            Console.WriteErrorLine("error: cannot write '" + llPath + "': " + wroteError.Message);
            return 1;
        }
        return 0;
    }

    if (o.Backend == "m68k")
        return BuildM68k(o, ir, baseName);
    if (o.Backend == "wasm")
        return BuildWasm(o, ir, baseName);

    string clang = LocateClang(o.Cc, windows);
    if (clang.Length == 0)
    {
        Console.WriteErrorLine("error: cannot find clang\n       Put clang in PATH (e.g. C:\\msys64\\clang64\\bin), set CSHIFT_CC or pass --cc <path>.");
        return 1;
    }
    string ccPath = windows ? clang.Replace("/", "\\") : clang;
    string optimize = "-O" + o.Optimize.ToString();
    string targetFlag = o.Target.Length > 0 ? " -target " + o.Target : "";
    // WebAssembly: the C library of WASI where clang does not look for it (wasi-sdk: <wasi-sdk>/share/wasi-sysroot)
    if (o.Target.ToLower().StartsWith("wasm") && Process.GetEnv("CSHIFT_WASI_SYSROOT") is string wasiSysroot)
        targetFlag += " --sysroot \"" + wasiSysroot + "\"";

    string objPath = "";
    string exePath = "";
    if (o.ObjectOnly)
    {
        objPath = (o.Output.Length > 0 && !o.FromProject) ? o.Output : baseName + objExt;
    }
    else
    {
        exePath = o.Output.Length > 0 ? o.Output : baseName + (windows ? ".exe" : "");
        if (o.FromProject && windows && !exePath.EndsWith(".exe"))
            exePath += ".exe";
    }
    string outPath = o.ObjectOnly ? objPath : exePath;
    EnsureParentDirectory(outPath);
    string llFile = outPath + ".ll";
    var written = File.WriteAllText(llFile, ir);
    if (written is error writtenError)
    {
        Console.WriteErrorLine("error: cannot write '" + llFile + "': " + writtenError.Message);
        return 1;
    }

    // Shims (generated C code for functions that take or return structs by value) are compiled with clang, which
    // knows the platform ABI.
    var shimObjects = List<string>.Create();
    foreach (var shim in shimSources)
    {
        string shimObject = Path.ChangeExtension(shim, objExt);
        var shimCommand = StringBuilder.Create();
        shimCommand.Append("\"" + ccPath + "\" -c" + targetFlag + " -O1 -I\"" + NativePath(Path.GetDirectory(shim), windows) + "\"");
        foreach (var inc in o.IncludePaths)
            shimCommand.Append(" -I\"" + NativePath(inc, windows) + "\"");
        foreach (var def in o.Defines)
            shimCommand.Append(" -D" + def);
        shimCommand.Append(" \"" + NativePath(shim, windows) + "\" -o \"" + NativePath(shimObject, windows) + "\"");
        if (o.Verbose)
            Console.WriteErrorLine(shimCommand.ToString());
        if (Process.Run(shimCommand.ToString()) != 0)
        {
            Console.WriteErrorLine("error: compiling the FFI shim '" + shim + "' failed");
            return 1;
        }
        shimObjects.Add(shimObject);
    }

    var command = StringBuilder.Create();
    command.Append("\"" + ccPath + "\" " + optimize + " -Wno-override-module" + targetFlag);
    if (o.ObjectOnly)
        command.Append(" -c");
    command.Append(" \"" + NativePath(llFile, windows) + "\" -o \"" + NativePath(outPath, windows) + "\"");
    if (!o.ObjectOnly)
    {
        foreach (var shimObject in shimObjects)
            command.Append(" \"" + NativePath(shimObject, windows) + "\"");
        foreach (var f in o.LibFiles)
            command.Append(" \"" + NativePath(f, windows) + "\"");
        foreach (var p in o.LibPaths)
            command.Append(" -L\"" + NativePath(p, windows) + "\"");
        foreach (var lib in cg.Links.ToArray())
            command.Append(" -l" + lib);
        if (!windows)
            command.Append(" -lm"); // the math functions of the standard library
        // 'thread' functions (stdlib/thread.csh). On Windows the static archive: the import library would make every
        // program depend on libwinpthread-1.dll, which is not part of the toolchain.
        command.Append(windows ? " -Wl,-Bstatic -lpthread -Wl,-Bdynamic" : " -lpthread");
        // WebAssembly: wasm-ld gives a program 64 KB of stack, which recursive code overflows into the heap; 8 MB like
        // the main thread of Linux
        if (o.Target.ToLower().StartsWith("wasm"))
            command.Append(" -Wl,-z,stack-size=8388608");
        foreach (var lib in o.Libs)
            command.Append(" -l" + lib);
    }
    if (o.Verbose)
        Console.WriteErrorLine(command.ToString());
    int code = Process.Run(command.ToString());
    if (!o.Verbose)
        File.Delete(llFile);
    if (!o.ObjectOnly)
    {
        foreach (var shimObject in shimObjects)
            File.Delete(shimObject);
    }
    else
    {
        foreach (var shimObject in shimObjects)
            Console.WriteLine("Also link " + shimObject + " (FFI wrappers)");
    }
    if (code != 0)
    {
        Console.WriteErrorLine(o.ObjectOnly ? "error: clang failed (exit code " + code.ToString() + ")" : "error: linking failed");
        return 1;
    }

    if (o.FromProject && !o.Run)
        Console.WriteLine("Built " + outPath);
    if (o.ObjectOnly)
        return 0;
    if (o.Run)
    {
        string runPath = NativePath(exePath, windows);
        if (!windows && runPath.IndexOf('/') < 0)
            runPath = "./" + runPath;
        return Process.Run("\"" + runPath + "\"");
    }
    return 0;
}

// Parses a source file and adds it to the compiler. Returns false after printing an error.
bool AddSource(const ref Compiler cg, Diagnostics diag, Ast tree, string path, bool prelude, List<FfiImport> imports)
{
    var text = ReadSource(path);
    if (text is string source)
    {
        AddSourceText(cg, diag, tree, path, source, prelude, imports);
        return true;
    }
    return false;
}

void AddSourceText(const ref Compiler cg, Diagnostics diag, Ast tree, string path, string source, bool prelude, List<FfiImport> imports)
{
    int file = diag.AddFile(path);
    var lexer = Lexer.Create(source, file, diag);
    int before = diag.ErrorCount();
    var parser = Parser.Create(lexer.Tokenize(), diag, tree);
    var unit = parser.ParseUnit(prelude);
    unit.File.Doc = lexer.FileDoc();
    cg.St[0].SyntaxErrors += diag.ErrorCount() - before;
    foreach (var imp in unit.Imports)
        imports.Add(FfiImport { Name = imp.Name, Header = imp.Header, SourcePath = path, Loc = imp.Loc });
    AddUnit(cg, unit);
}

// ---------------------------------------------------------------------------
// check / query (the VS Code extension)
// ---------------------------------------------------------------------------

// A path in the form in which two names of the same file compare equal (full, '/' separators; lower case on Windows).
string SamePath(string path)
{
    string full = Path.GetFullPath(path);
    return Process.IsWindows() ? full.ToLower() : full;
}

// The cshift.json in the folder of the file or the nearest folder above it ("" if there is none: the file alone).
string ProjectAbove(string file)
{
    string dir = Path.GetDirectory(Path.GetFullPath(file));
    for (var level = 0; level < 64 && dir.Length > 0; level += 1)
    {
        string candidate = Path.Combine(dir, "cshift.json");
        if (File.Exists(candidate))
            return candidate;
        string parent = Path.GetDirectory(dir);
        if (parent == dir)
            break;
        dir = parent;
    }
    return "-"; // no project: LoadProject fails and the file is checked alone
}

// The number in the text (0 if it is none).
int64 ParseNumber(string text)
{
    int64 n = 0;
    foreach (var c in text)
    {
        if (c < '0' || c > '9')
            return 0;
        n = n * 10 + (int64)((int)c - 48);
    }
    return n;
}

// The JSON answer of 'cshiftc query': {"hover": "...", "definition": {"file": "...", "line": n, "col": n}} for the name
// at the position, {} if there is none. The definition is left out when it is not in a file (the embedded standard
// library, a builtin).
string QueryAnswer(const ref Compiler cg, Diagnostics diag, BuildOptions o, Ast tree)
{
    string target = SamePath(o.AtFile);
    int file = -1;
    for (var i = 0; i < diag.Files.Count(); i += 1)
    {
        string name = diag.Files.Get(i);
        if (!name.StartsWith("<") && SamePath(name) == target)
            file = i;
    }
    if (file < 0)
        return "{}";
    if (o.OutlineFile.Length > 0)
        return "{\"symbols\": " + OutlineJson(cg, file) + "}";
    int found = FindIndexEntry(cg, file, o.AtLine, o.AtCol);
    if (found < 0)
        return "{}";
    var e = cg.Index.Get(found);
    string answer = "{\"hover\": " + JsonString(e.Hover);
    string doc = e.Def.Line > 0 ? DocAt(cg, e.Def) : BuiltinDocOf(LoadBuiltinDocs(o, diag, tree), e.Hover);
    if (doc.Length > 0)
        answer += ", \"doc\": " + JsonString(DocMarkdown(doc));
    if (e.Def.Line > 0 && e.Def.File >= 0 && e.Def.File < diag.Files.Count() && !diag.Files.Get(e.Def.File).StartsWith("<"))
        answer += ", \"definition\": {\"file\": " + JsonString(Path.GetFullPath(diag.Files.Get(e.Def.File))) + ", \"line\": " +
                  e.Def.Line.ToString() + ", \"col\": " + e.Def.Col.ToString() + "}";
    if (o.References)
        answer += ", \"references\": " + ReferencesJson(cg, diag, found);
    if (o.Members)
        answer += ", \"members\": " + MembersJson(cg, e.Type, e.IsTypeName);
    return answer + "}";
}

// The folders of stdlib/os that a target uses: windows; posix and the struct layouts of its architecture; none for
// AmigaOS (stdlib/amiga has the same functions).
List<string> OsLayers(string target, string backend, bool windows)
{
    var layers = List<string>.Create();
    string lower = target.ToLower();
    if (lower.Contains("amigaos"))
        return layers;
    if (windows)
    {
        layers.Add("windows");
        return layers;
    }
    if (lower.StartsWith("wasm"))
    {
        layers.Add("wasi"); // WebAssembly: a POSIX-like C library with a 64-bit time_t
        return layers;
    }
    layers.Add("posix");
    string arch = lower;
    int dash = arch.IndexOf('-');
    if (dash >= 0)
        arch = arch.Substring(0, dash).ToString();
    if (arch == "m68k" || backend == "m68k")
        layers.Add("posix-m68k");
    else if (target.Length > 0 && TargetInfo.Has32BitPointers(arch))
        layers.Add("posix-32");
    else
        layers.Add("posix-64");
    return layers;
}

// The declarations of the built-in types (stdlib/builtin/*.csh: string, the numbers, arrays, Console, ...), parsed
// for their doc comments only (cshiftc doc, the hover); from --stdlib or the copy embedded in cshc.
List<CompilationUnit> LoadBuiltinDocs(BuildOptions o, Diagnostics diag, Ast tree)
{
    var units = List<CompilationUnit>.Create();
    var names = List<string>.Create();
    var texts = List<string>.Create();
    if (o.Stdlib.Length == 0)
    {
        for (var i = 0; i < EmbeddedBuiltinNames.Length; i += 1)
        {
            names.Add("<stdlib>/builtin/" + EmbeddedBuiltinNames[i]);
            texts.Add(EmbeddedBuiltinTexts[i]);
        }
    }
    else if (o.Stdlib != "-")
    {
        foreach (var path in Directory.FindFiles(Path.Combine(o.Stdlib, "builtin"), ".csh").ToArray())
        {
            if (ReadSource(path) is string text)
            {
                names.Add(path);
                texts.Add(text);
            }
        }
    }
    for (var i = 0; i < names.Count(); i += 1)
    {
        int file = diag.AddFile(names.Get(i));
        var lexer = Lexer.Create(texts.Get(i), file, diag);
        var parser = Parser.Create(lexer.Tokenize(), diag, tree);
        parser.DeclarationsOnly = true;
        var unit = parser.ParseUnit(true);
        unit.File.Doc = lexer.FileDoc();
        units.Add(unit);
    }
    return units;
}

// The name the compiler was started with (for hints like "cshiftc run"): the file name of the executable without .exe.
string CompilerName()
{
    string name = Path.GetFileName(Host.ExecutablePath());
    if (name.ToLower().EndsWith(".exe"))
        name = name.Substring(0, name.Length - 4).ToString();
    return name.Length > 0 ? name : "cshiftc";
}

// The m68k backend (selfhost/src/M68k): the IR becomes 68000 assembly.
int BuildM68k(BuildOptions o, string ir, string baseName)
{
    bool amiga = o.Target.Contains("amigaos");
    var text = M68kAssembly(ir, amiga ? AmigaStartupAsm(262144) : "", o.Optimize); // the startup code comes first
    if (text is error failed)
    {
        Console.WriteErrorLine("error: m68k backend: " + failed.Message);
        return 1;
    }
    string asm = "";
    if (text is string generated)
        asm = generated;
    if (o.EmitAsm)
        return WriteOutput(o.Output.Length == 0 ? baseName + ".s" : (o.FromProject ? o.Output + ".s" : o.Output), asm);

    var assembled = Assemble(asm);
    if (assembled is error asmError)
    {
        Console.WriteErrorLine("error: m68k backend: " + asmError.Message);
        return 1;
    }
    if (assembled is AsmObject obj)
    {
        if (o.ObjectOnly)
        {
            // an ELF object: for m68k Linux (the tests of the backend)
            string path = o.Output.Length > 0 && !o.FromProject ? o.Output : baseName + ".o";
            return WriteBytesOutput(path, WriteElfObject(obj));
        }
        if (!amiga)
        {
            Console.WriteErrorLine("error: the m68k backend writes executables for AmigaOS only (for '" + o.Target + "': use -c or --emit-asm)");
            return 1;
        }
        var exe = WriteHunkExecutable(obj);
        if (exe is error exeError)
        {
            Console.WriteErrorLine("error: " + exeError.Message);
            return 1;
        }
        if (exe is uint8[] exeBytes)
            return WriteBytesOutput(o.Output.Length > 0 ? o.Output : baseName, exeBytes);
        return 1;
    }
    return 1;
}

// The wasm backend (selfhost/src/Wasm): the IR becomes a WebAssembly module, without clang.
int BuildWasm(BuildOptions o, string ir, string baseName)
{
    if (o.ObjectOnly)
    {
        Console.WriteErrorLine("error: the wasm backend writes whole programs only (no -c)");
        return 1;
    }
    var module = ReadModule(ir);
    if (module is error readError)
    {
        Console.WriteErrorLine("error: wasm backend: " + readError.Message);
        return 1;
    }
    if (module is IrModule m)
    {
        var warnings = List<string>.Create();
        var bytes = GenerateWasm(m, warnings);
        foreach (var warning in warnings.ToArray())
            Console.WriteErrorLine("warning: " + warning);
        if (bytes is error genError)
        {
            Console.WriteErrorLine("error: wasm backend: " + genError.Message);
            return 1;
        }
        if (bytes is uint8[] wasm)
            return WriteBytesOutput(o.Output.Length > 0 ? o.Output : baseName, wasm);
    }
    return 1;
}

// The C library of CShift (stdlib/libc: printf's formatting) is a part of the programs of the backends that bring
// their own C library: AmigaOS and WebAssembly.
bool HasOwnLibc(BuildOptions o)
{
    return (o.Backend == "m68k" && o.Target.Contains("amigaos")) || o.Backend == "wasm";
}

int WriteOutput(string path, string text)
{
    EnsureParentDirectory(path);
    var wrote = File.WriteAllText(path, text);
    if (wrote is error wroteError)
    {
        Console.WriteErrorLine("error: cannot write '" + path + "': " + wroteError.Message);
        return 1;
    }
    return 0;
}

int WriteBytesOutput(string path, uint8[] bytes)
{
    EnsureParentDirectory(path);
    var wrote = File.WriteAllBytes(path, bytes);
    if (wrote is error wroteError)
    {
        Console.WriteErrorLine("error: cannot write '" + path + "': " + wroteError.Message);
        return 1;
    }
    return 0;
}

Error<string> M68kAssembly(string ir, string prelude, int optimize)
{
    var module = try ReadModule(ir);
    return try GenerateModule(module, prelude, optimize);
}
