// The command line of cshc: single files and projects (port of the driver part of compiler/src/main.cpp).
//
//     cshc [options] file.csh [file2.csh ...]     compile single files
//     cshc build [project] [options]              build a project (cshift.json)
//     cshc run   [project] [options]              build and run a project
//     cshc new   <directory>                      create a new project
//
// The code generator writes LLVM IR as text; clang optimizes it, generates the object code and links.

namespace CShift.Driver;

using System;
using CShift.Syntax;
using CShift.CodeGen;

struct BuildOptions
{
    List<string> Inputs;
    string Output;
    string Target;
    string Cc;
    string Stdlib;
    string FfiTool;
    string ProjectDir;
    List<FfiImport> Imports;    // "using X from header" declarations found in the sources
    int Optimize;
    bool OptimizeGiven;
    bool ObjectOnly;
    bool EmitLlvm;
    bool Run;
    bool Verbose;
    bool ArcStats;
    List<string> Libs;          // -l<name>
    List<string> LibFiles;      // .a/.o/.lib files for the linker
    List<string> LibPaths;      // -L<dir>
    List<string> IncludePaths;  // -I<dir>
    List<string> Defines;       // -D<name>
    List<string> ApiPaths;      // --ffi-api=<text>
    bool FromProject;
    string ProjectName;

    static BuildOptions Create()
    {
        var o = BuildOptions { Output = "", Target = "", Cc = "", Stdlib = "", FfiTool = "", ProjectDir = "", Optimize = 2, ProjectName = "" };
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

void PrintUsage()
{
    Console.WriteErrorLine("cshc - the CShift compiler written in CShift\n\n" +
        "usage: cshc [options] file.csh [file2.csh ...]     compile single files\n" +
        "       cshc build [project] [options]              build a project (cshift.json)\n" +
        "       cshc run   [project] [options]              build and run a project\n" +
        "       cshc new   <directory>                      create a new project\n\n" +
        "options:\n" +
        "  -o <file>          output file\n" +
        "  -c                 compile to an object file only (no linking)\n" +
        "  --emit-llvm        write LLVM IR (.ll) instead of an executable\n" +
        "  -O0 .. -O3         optimization level (default -O2)\n" +
        "  --target <triple>  target triple (default: host)\n" +
        "  --cc <program>     clang program (default: CSHIFT_CC, then clang)\n" +
        "  --stdlib <dir>     use this standard library instead of the embedded one\n" +
        "  -l<name>, -L<dir>  link a library / library search path\n" +
        "  file.a, file.o     libraries and object files are passed to the linker\n" +
        "  --run              run the program after building\n" +
        "  --arc-stats        debug: print heap allocations/frees when the program exits\n" +
        "  -v                 verbose output");
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
        else if (a == "--ffi-tool" && i + 1 < args.Length)
        {
            i += 1;
            o.FfiTool = args[i];
        }
        else if (a == "--no-stdlib")
            o.Stdlib = "-";
        else if (a == "-c")
            o.ObjectOnly = true;
        else if (a == "--emit-llvm")
            o.EmitLlvm = true;
        else if (a == "--arc-stats")
            o.ArcStats = true;
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
        Console.WriteLine("cshc dev");
        return 0;
    }

    var o = BuildOptions.Create();
    string command = "compile";
    int first = 0;
    if (args[0] == "build" || args[0] == "run" || args[0] == "new")
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
        if (!created)
        {
            Console.WriteErrorLine("error: " + created.Message);
            return 1;
        }
        Console.WriteLine("Created project '" + dir + "'\n  cd " + dir + "\n  cshc run");
        return 0;
    }

    if (command == "build" || command == "run")
    {
        string location = o.Inputs.Count() > 0 ? o.Inputs.Get(0) : "";
        var loaded = LoadProject(location);
        if (loaded is Project project)
        {
            o.FromProject = true;
            o.ProjectName = project.Name;
            o.ProjectDir = project.Dir;
            o.Inputs = project.Sources;
            if (o.Output.Length == 0)
                o.Output = project.Output;
            if (!o.OptimizeGiven && project.HasOptimize)
                o.Optimize = project.Optimize;
            if (o.Target.Length == 0)
                o.Target = project.Target;
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
            if (project.Type == "object")
                o.ObjectOnly = true;
            if (command == "run")
                o.Run = true;
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

// A cc that works: --cc, then CSHIFT_CC, then clang from PATH, then the usual MSYS2 folders on Windows.
string LocateClang(string cc, bool windows)
{
    if (cc.Length > 0)
        return cc;
    var fromEnv = Process.GetEnv("CSHIFT_CC");
    if (fromEnv is string configured)
    {
        if (configured.Length > 0)
            return configured;
    }
    string quiet = windows ? " > nul 2>&1" : " > /dev/null 2>&1";
    if (Process.Run("clang --version" + quiet) == 0)
        return "clang";
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
    else
    {
        if (Process.Run("cc --version" + quiet) == 0)
            return "cc";
        if (Process.Run("gcc --version" + quiet) == 0)
            return "gcc";
    }
    return "";
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
    var cg = Compiler.Create(tree, diag, windows);
    cg.St[0].ArcStats = o.ArcStats;

    // The standard library (stdlib/*.csh) is parsed as a prelude: its functions are only compiled when they are used.
    // Without --stdlib the copy that is embedded in cshc is used (src/Driver/EmbeddedStdlib.csh).
    if (o.Stdlib.Length == 0)
    {
        string[] names = EmbeddedStdlibNames();
        string[] texts = EmbeddedStdlibTexts();
        for (var i = 0; i < names.Length; i += 1)
            AddSourceText(cg, diag, tree, "<stdlib>/" + names[i], texts[i], true, o.Imports);
        cg.St[0].StdlibLoaded = names.Length > 0;
    }
    else if (o.Stdlib != "-")
    {
        var libFiles = Directory.FindFiles(o.Stdlib, ".csh");
        foreach (var libFile in libFiles)
        {
            if (!AddSource(cg, diag, tree, libFile, true, o.Imports))
                return 1;
        }
        cg.St[0].StdlibLoaded = libFiles.Count() > 0;
    }
    foreach (var path in o.Inputs)
    {
        if (!AddSource(cg, diag, tree, path, false, o.Imports))
            return 1;
    }
    if (diag.HasErrors())
        return 1;

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
            var loaded = LoadFfiUnit(files.FfiPath, imp.Name, diag, tree);
            if (loaded is CompilationUnit ffiUnit)
                AddUnit(cg, ffiUnit);
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

    // ---- output files ----
    string first = o.Inputs.Get(0);
    string baseName = o.Output.Length > 0 ? o.Output : StemOf(first);
    string objExt = windows ? ".obj" : ".o";

    if (o.EmitLlvm)
    {
        string llPath = o.Output.Length == 0 ? baseName + ".ll" : (o.FromProject ? o.Output + ".ll" : o.Output);
        EnsureParentDirectory(llPath);
        var wrote = File.WriteAllText(llPath, ir);
        if (!wrote)
        {
            Console.WriteErrorLine("error: cannot write '" + llPath + "': " + wrote.Message);
            return 1;
        }
        return 0;
    }

    string clang = LocateClang(o.Cc, windows);
    if (clang.Length == 0)
    {
        Console.WriteErrorLine("error: cannot find clang\n       Put clang in PATH (e.g. C:\\msys64\\clang64\\bin), set CSHIFT_CC or pass --cc <path>.");
        return 1;
    }
    string ccPath = windows ? clang.Replace("/", "\\") : clang;
    string optimize = "-O" + o.Optimize.ToString();
    string targetFlag = o.Target.Length > 0 ? " -target " + o.Target : "";

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
    if (!written)
    {
        Console.WriteErrorLine("error: cannot write '" + llFile + "': " + written.Message);
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
bool AddSource(Compiler cg, Diagnostics diag, Ast tree, string path, bool prelude, List<FfiImport> imports)
{
    var text = ReadSource(path);
    if (text is string source)
    {
        AddSourceText(cg, diag, tree, path, source, prelude, imports);
        return true;
    }
    return false;
}

void AddSourceText(Compiler cg, Diagnostics diag, Ast tree, string path, string source, bool prelude, List<FfiImport> imports)
{
    int file = diag.AddFile(path);
    var lexer = Lexer.Create(source, file, diag);
    var parser = Parser.Create(lexer.Tokenize(), diag, tree);
    var unit = parser.ParseUnit(prelude);
    foreach (var imp in unit.Imports)
        imports.Add(FfiImport { Name = imp.Name, Header = imp.Header, SourcePath = path, Loc = imp.Loc });
    AddUnit(cg, unit);
}
