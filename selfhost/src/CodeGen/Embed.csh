// Files that are embedded into the program at compile time (paths are relative to the source file with the call):
//
//     EmbedText("file")            the text of a file (string)
//     EmbedNames("dir", ".ext")    the names of the files of a directory with this extension, sorted (string[])
//     EmbedTexts("dir", ".ext")    their texts in the same order (string[])
//
// CShift has no other way to put a file into a program. cshc uses it for its standard library. Line ends are normalized
// to '\n' and a byte order mark is removed. (Same in the C++ compiler: CodeGen::emitEmbed.)

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

bool IsEmbedName(string name)
{
    return name == "EmbedText" || name == "EmbedTexts" || name == "EmbedNames";
}

string ReadEmbedded(Compiler cg, string name, string path, SourceLoc loc)
{
    var read = File.ReadAllText(path);
    string text = "";
    if (read is string content)
        text = content;
    else
        Fail(cg, loc, name + ": cannot read '" + path + "'");
    if (text.Length >= 3 && text[0] == (char)0xEF && text[1] == (char)0xBB && text[2] == (char)0xBF)
        text = text.Substring(3);
    return text.Replace("\r", "");
}

Value EmitEmbed(Compiler cg, Expr e, CallExpr call, string name)
{
    var types = cg.Types;
    var ir = cg.Ir;
    int wanted = name == "EmbedText" ? 1 : 2;
    if (call.Args.Length != wanted)
        Fail(cg, e.Loc, name + " takes " + wanted.ToString() + " string literal argument(s)");
    var literals = new string[wanted];
    for (var i = 0; i < wanted; i += 1)
    {
        if (call.Args[i].Kind != ExprKind.StringLit)
            Fail(cg, call.Args[i].Loc, name + " needs string literals (the files are read when the program is compiled)");
        literals[i] = cg.Tree.GetStringLit(call.Args[i]).Value;
    }
    string source = cg.Diag.Files.Get(e.Loc.File);
    string baseDir = Path.GetDirectory(source);

    if (name == "EmbedText")
        return Rvalue(types.String, ir.StringLiteral(ReadEmbedded(cg, name, Path.Combine(baseDir, literals[0]), e.Loc)), false);

    string dir = Path.Combine(baseDir, literals[0]);
    if (!Directory.Exists(dir))
        Fail(cg, e.Loc, name + ": '" + dir + "' is not a directory");
    var names = List<string>.Create();
    foreach (var entry in Directory.GetEntries(dir))
    {
        bool matches = literals[1].Length == 0 || entry.EndsWith(literals[1]);
        if (matches && !Directory.Exists(Path.Combine(dir, entry)))
            names.Add(entry);
    }

    int arrayType = types.ArrayOf(types.String);
    string arr = AllocArray(cg, types.String, names.Count().ToString());
    for (var i = 0; i < names.Count(); i += 1)
    {
        string text = name == "EmbedNames" ? names.Get(i) : ReadEmbedded(cg, name, Path.Combine(dir, names.Get(i)), e.Loc);
        string slot = ir.Gep("ptr", DataPtr(cg, arr), "i64 " + i.ToString());
        ir.Store("ptr", ir.StringLiteral(text), slot); // string literals are never freed, so no retain is needed
    }
    return Rvalue(arrayType, arr, true);
}
