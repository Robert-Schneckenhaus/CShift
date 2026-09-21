// cshc: the CShift compiler, written in CShift.
//
//     cshc [options] file.csh [file2.csh ...]     compile (needs clang for the last steps)
//         -o <file>       output file
//         --emit-llvm     write the LLVM IR (.ll) and stop
//         -O0 .. -O3      optimization level (default -O2)
//         --cc <program>  clang program to use
//         --run           run the program after building
//     cshc --tokens file.csh     token dump (compare with: cshiftc --dump-tokens file.csh)
//     cshc --ast file.csh        syntax tree dump (compare with: cshiftc --dump-ast file.csh)

using System;
using CShift.Syntax;
using CShift.CodeGen;

int Main(string[] args)
{
    if (args.Length == 2 && args[0] == "--tokens")
        return DumpTokens(args[1]);
    if (args.Length == 2 && args[0] == "--ast")
        return DumpSyntaxTree(args[1]);
    return Compile(args);
}

// Reads a source file (a UTF-8 byte order mark is skipped).
Optional<string> ReadSource(string path)
{
    var text = File.ReadAllText(path);
    if (text is string source)
    {
        if (source.Length >= 3 && source[0] == (char)0xEF && source[1] == (char)0xBB && source[2] == (char)0xBF)
            return source.Substring(3, source.Length - 3);
        return source;
    }
    Console.WriteErrorLine("error: cannot read '" + path + "'");
    return null;
}

int DumpTokens(string path)
{
    var text = ReadSource(path);
    if (text is string source)
    {
        var diag = Diagnostics.Create();
        int file = diag.AddFile(path);
        var lexer = Lexer.Create(source, file, diag);
        var tokens = lexer.Tokenize();
        foreach (var t in tokens)
            Console.WriteLine(DumpToken(t));
        return diag.HasErrors() ? 1 : 0;
    }
    return 1;
}

int DumpSyntaxTree(string path)
{
    var text = ReadSource(path);
    if (text is string source)
    {
        var diag = Diagnostics.Create();
        int file = diag.AddFile(path);
        var lexer = Lexer.Create(source, file, diag);
        var tokens = lexer.Tokenize();
        var tree = Ast.Create();
        var parser = Parser.Create(tokens, diag, tree);
        var unit = parser.ParseUnit(false);
        var dumper = AstDumper.Create(tree);
        dumper.DumpUnit(unit);
        Console.Write(dumper.Out.ToString());
        return diag.HasErrors() ? 1 : 0;
    }
    return 1;
}

// The file name without directory and extension.
string StemOf(string path)
{
    int slash = path.LastIndexOf('/');
    int back = path.LastIndexOf('\\');
    if (back > slash)
        slash = back;
    string name = slash >= 0 ? path.Substring(slash + 1, path.Length - slash - 1) : path;
    int dot = name.LastIndexOf('.');
    return dot > 0 ? name.Substring(0, dot) : name;
}

int Compile(string[] args)
{
    var inputs = List<string>.Create();
    string output = "";
    string cc = "clang";
    string optimize = "-O2";
    bool emitLlvm = false;
    bool run = false;
    bool verbose = false;
    for (var i = 0; i < args.Length; i += 1)
    {
        string a = args[i];
        if (a == "-o" && i + 1 < args.Length)
        {
            i += 1;
            output = args[i];
        }
        else if (a == "--cc" && i + 1 < args.Length)
        {
            i += 1;
            cc = args[i];
        }
        else if (a == "--emit-llvm")
            emitLlvm = true;
        else if (a == "--run")
            run = true;
        else if (a == "-v")
            verbose = true;
        else if (a == "-O0" || a == "-O1" || a == "-O2" || a == "-O3")
            optimize = a;
        else if (a.Length > 0 && a[0] == '-')
        {
            Console.WriteErrorLine("error: unknown option '" + a + "'");
            return 2;
        }
        else
            inputs.Add(a);
    }
    if (inputs.Count() == 0)
    {
        Console.WriteErrorLine("usage: cshc [-o file] [--emit-llvm] [-O0..-O3] [--cc clang] [--run] file.csh [file2.csh ...]");
        return 2;
    }

    // Parse all files.
    var diag = Diagnostics.Create();
    var tree = Ast.Create();
    bool windows = Process.IsWindows();
    var cg = Compiler.Create(tree, diag, windows);
    for (var i = 0; i < inputs.Count(); i += 1)
    {
        string path = inputs.Get(i);
        var text = ReadSource(path);
        if (text is string source)
        {
            int file = diag.AddFile(path);
            var lexer = Lexer.Create(source, file, diag);
            var parser = Parser.Create(lexer.Tokenize(), diag, tree);
            AddUnit(cg, parser.ParseUnit(false));
        }
        else
        {
            return 1;
        }
    }
    if (diag.HasErrors())
        return 1;

    string ir = CompileProgram(cg, "");

    if (output.Length == 0)
        output = StemOf(inputs.Get(0)) + (emitLlvm ? ".ll" : (windows ? ".exe" : ""));
    string llFile = emitLlvm ? output : output + ".ll";
    var written = File.WriteAllText(llFile, ir);
    if (!written)
    {
        Console.WriteErrorLine("error: cannot write '" + llFile + "': " + written.Message);
        return 1;
    }
    if (emitLlvm)
        return 0;

    string command = "\"" + cc + "\" " + optimize + " -Wno-override-module \"" + llFile + "\" -o \"" + output + "\"";
    foreach (var lib in cg.Links.ToArray())
        command += " -l" + lib;
    if (verbose)
        Console.WriteErrorLine(command);
    int code = Process.Run(command);
    if (code != 0)
    {
        Console.WriteErrorLine("error: clang failed (exit code " + code.ToString() + ")");
        return 1;
    }
    if (!verbose)
        File.Delete(llFile);
    if (run)
        return Process.Run("\"" + output + "\"");
    return 0;
}
