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
using CShift.Driver;

int Main(string[] args)
{
    if (args.Length == 2 && args[0] == "--tokens")
        return DumpTokens(args[1]);
    if (args.Length == 2 && args[0] == "--ast")
        return DumpSyntaxTree(args[1]);
    return Cshc(args);
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
