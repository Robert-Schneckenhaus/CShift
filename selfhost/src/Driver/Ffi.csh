// Importing C headers: "using Geo from "geo.h";" (port of the reading side of compiler/src/FfiImport.cpp).
//
// A header is turned into a .ffi file (JSON with the functions, structs, enums and constants and their CShift types)
// by libclang (FfiGenerator.csh); it is cached in obj/ffi and generated again when the header, the options or a header
// it includes change. A ready-made .ffi file is used as it is. See FFI.md.

namespace CShift.Driver;

using System;
using CShift.Syntax;

struct FfiImport
{
    string Name;          // namespace name
    string Header;        // as written: "sqlite3.h" or "bindings/sqlite3.ffi"
    string SourcePath;    // the file that imports it
    SourceLoc Loc;
}

struct FfiFiles
{
    string FfiPath;
    List<string> Shims;   // generated C files to compile and link (functions that take structs by value)
}

// ---- reading JSON values ----

string JsonString(Json json, int obj, string key, string fallback)
{
    int v = json.Get(obj, key);
    if (v < 0 || json.KindOf(v) != JsonKind.String)
        return fallback;
    return json.Text(v);
}

bool JsonBool(Json json, int obj, string key)
{
    int v = json.Get(obj, key);
    return v >= 0 && json.KindOf(v) == JsonKind.Bool && json.Nodes.Get(v).Flag;
}

// The value as an integer: JSON numbers, or decimal strings for values above the range of int64.
// Returns false if there is no such value. The result is a sign and a magnitude.
bool JsonInteger(Json json, int obj, string key, ref bool negative, ref uint64 magnitude)
{
    int v = json.Get(obj, key);
    if (v < 0)
        return false;
    var kind = json.KindOf(v);
    if (kind != JsonKind.Number && kind != JsonKind.String)
        return false;
    string text = json.Text(v);
    negative = text.Length > 0 && text[0] == '-';
    uint64 value = 0;
    for (var i = negative ? 1 : 0; i < text.Length; i += 1)
    {
        char c = text[i];
        if (c < '0' || c > '9')
            break;
        value = unchecked(value * 10 + (uint64)((int)c - 48));
    }
    magnitude = value;
    return true;
}

int64 JsonInt(Json json, int obj, string key, int64 fallback)
{
    bool negative = false;
    uint64 magnitude = 0;
    if (!JsonInteger(json, obj, key, ref negative, ref magnitude))
        return fallback;
    return negative ? -(int64)magnitude : (int64)magnitude;
}

// ---- preparing the .ffi file ----

// The names of the shim sources that a .ffi file lists ("shim" is a file next to it).
List<string> ShimsOf(string ffiPath)
{
    var shims = List<string>.Create();
    var read = File.ReadAllText(ffiPath);
    if (read is string text)
    {
        var json = Json.Create(text);
        var parsed = json.ParseDocument();
        if (parsed is int root)
        {
            string shim = JsonString(json, root, "shim", "");
            if (shim.Length > 0)
                shims.Add(Path.Combine(Path.GetDirectory(ffiPath), shim));
        }
    }
    return shims;
}

// Returns an up-to-date .ffi file for the import.
Error<FfiFiles> PrepareFfi(FfiImport imp, BuildOptions o, string cacheDir)
{
    string baseDir = Path.GetDirectory(imp.SourcePath);
    string baseArg = baseDir.Length > 0 ? baseDir : ".";

    // A ready-made .ffi file is used as it is.
    if (imp.Header.EndsWith(".ffi"))
    {
        string file = IsAbsolutePath(imp.Header) ? imp.Header : Path.Combine(baseArg, imp.Header);
        if (!File.Exists(file))
            return error("cannot find the FFI file '" + imp.Header + "' (looked for '" + file + "')");
        return FfiFiles { FfiPath = file, Shims = ShimsOf(file) };
    }

    string ffiPath = Path.Combine(cacheDir, SanitizeName(imp.Name) + ".ffi");
    var options = FfiOptionsOf(o, LocateClang(o.Cc, Process.IsWindows()));
    string why = "not generated yet";
    if (File.Exists(ffiPath) && IsFfiFresh(ffiPath, imp.Header, options, ref why))
    {
        if (o.Verbose)
            Console.WriteErrorLine("ffi: '" + imp.Name + "' is up to date (" + ffiPath + ")");
        return FfiFiles { FfiPath = ffiPath, Shims = ShimsOf(ffiPath) };
    }
    if (o.Verbose)
        Console.WriteErrorLine("ffi: generating '" + ffiPath + "' from \"" + imp.Header + "\" (" + why + ")");
    if (!Directory.Create(cacheDir))
        return error("cannot create '" + cacheDir + "'");
    try GenerateFfi(imp.Name, imp.Header, baseArg, options, ffiPath);
    return FfiFiles { FfiPath = ffiPath, Shims = ShimsOf(ffiPath) };
}

FfiOptions FfiOptionsOf(BuildOptions o, string clang)
{
    string target = o.Target;
    if (target.Length == 0 && clang.Length > 0)
    {
        // the host triple, as the clang that links the program sees it
        var printed = Process.RunCapture("\"" + (Process.IsWindows() ? clang.Replace("/", "\\") : clang) + "\" -print-target-triple");
        if (printed is string text)
            target = text.Trim();
    }
    return FfiOptions { Target = target, IncludePaths = o.IncludePaths, Defines = o.Defines, ApiPaths = o.ApiPaths, Clang = clang, Verbose = o.Verbose };
}

string SanitizeName(string name)
{
    var bytes = new uint8[name.Length];
    for (var i = 0; i < name.Length; i += 1)
    {
        char c = name[i];
        bytes[i] = Char.IsLetterOrDigit(c) || c == '_' || c == '-' ? (uint8)c : (uint8)'_';
    }
    return string.FromBytes(bytes);
}

// A cached .ffi file is used while the header, the options and every header it depends on are unchanged.
bool IsFfiFresh(string ffiPath, string header, FfiOptions options, ref string why)
{
    var read = File.ReadAllText(ffiPath);
    if (read is string text)
    {
        var json = Json.Create(text);
        var parsed = json.ParseDocument();
        if (parsed is int root)
        {
            if (json.KindOf(root) != JsonKind.Object)
            {
                why = "not a JSON object";
                return false;
            }
            if (JsonInt(json, root, "format", -1) != FfiFormat())
            {
                why = "format changed";
                return false;
            }
            if (JsonString(json, root, "header", "") != header)
            {
                why = "different header";
                return false;
            }
            if (JsonString(json, root, "target", "") != options.Target)
            {
                why = "different target";
                return false;
            }
            var flags = FfiFlags(options);
            int recorded = json.Get(root, "flags");
            if (recorded < 0 || json.KindOf(recorded) != JsonKind.Array || json.Nodes.Get(recorded).Items.Count() != flags.Count())
            {
                why = "different compiler flags";
                return false;
            }
            var items = json.Nodes.Get(recorded).Items;
            for (var i = 0; i < flags.Count(); i += 1)
            {
                int item = items.Get(i);
                if (json.KindOf(item) != JsonKind.String || json.Text(item) != flags.Get(i))
                {
                    why = "different compiler flags";
                    return false;
                }
            }
            int deps = json.Get(root, "dependencies");
            if (deps < 0 || json.KindOf(deps) != JsonKind.Array || json.Nodes.Get(deps).Items.Count() == 0)
            {
                why = "no dependency information";
                return false;
            }
            foreach (var dep in json.Nodes.Get(deps).Items)
            {
                string path = JsonString(json, dep, "path", "");
                string hash = FfiHashFile(path);
                if (hash.Length == 0)
                {
                    why = "'" + path + "' is missing";
                    return false;
                }
                if (hash != JsonString(json, dep, "hash", ""))
                {
                    why = "'" + path + "' changed";
                    return false;
                }
            }
            return true;
        }
        why = "not valid JSON";
        return false;
    }
    why = "unreadable";
    return false;
}

// ---- creating the declarations ----

struct FfiBuilder
{
    Diagnostics Diag;
    Ast Tree;
    string FfiPath;
    SourceLoc Loc;
    int[] Failed;

    TypeRef MakeType(string text, string what)
    {
        if (text.Length == 0)
        {
            Problem(what + ": missing type");
            return TypeRef { };
        }
        var local = Diagnostics.Create();
        local.AddFile(FfiPath);
        var lexer = Lexer.Create(text, 0, local);
        var tokens = lexer.Tokenize();
        var parser = Parser.Create(tokens, local, Tree);
        var parsed = parser.ParseStandaloneType();
        if (parsed is TypeRef t)
        {
            if (!local.HasErrors())
                return t;
        }
        Problem(what + ": invalid type '" + text + "'");
        return TypeRef { };
    }

    Expr MakeInteger(bool negative, uint64 magnitude)
    {
        Expr lit = Tree.AddIntLit(Loc, IntLitExpr { Value = magnitude });
        if (!negative)
            return lit;
        return Tree.AddUnary(Loc, UnaryExpr { Op = UnOp.Neg, Operand = lit });
    }

    void Problem(string message)
    {
        Diag.ReportAt(SourceLoc { }, FfiPath + ": " + message);
        Failed[0] = 1;
    }
}

Error<CompilationUnit> LoadFfiUnit(string ffiPath, string name, Diagnostics diag, Ast tree)
{
    var read = File.ReadAllText(ffiPath);
    string text = "";
    if (read is string content)
        text = content;
    else
        return error("cannot read '" + ffiPath + "'");
    var json = Json.Create(text);
    var parsed = json.ParseDocument();
    int root = 0;
    if (parsed is int rootNode)
        root = rootNode;
    else
        return error(ffiPath + ": invalid JSON: " + parsed.Message);
    if (json.KindOf(root) != JsonKind.Object)
        return error(ffiPath + ": the FFI file must contain a JSON object");
    if (JsonInt(json, root, "format", -1) != 2)
        return error(ffiPath + ": unsupported FFI format (expected 2)");

    int fileId = diag.AddFile(ffiPath);
    var unit = CompilationUnit.Create(fileId, true); // library declarations are only compiled when they are used
    unit.File.Ns = name;
    var b = FfiBuilder { Diag = diag, Tree = tree, FfiPath = ffiPath, Loc = SourceLoc { File = fileId, Line = 1, Col = 1 }, Failed = new int[1] };

    int structs = json.Get(root, "structs");
    if (structs >= 0 && json.KindOf(structs) == JsonKind.Array)
    {
        foreach (var sv in json.Nodes.Get(structs).Items)
        {
            if (json.KindOf(sv) != JsonKind.Object)
                continue;
            var s = StructDecl { Loc = b.Loc, Name = JsonString(json, sv, "name", ""), ExplicitLayout = true };
            s.TypeParams = new string[0];
            s.Bases = new TypeRef[0];
            s.Constraints = new Constraint[0];
            s.Methods = new FuncDecl[0];
            s.Opaque = JsonBool(json, sv, "opaque");
            s.LayoutSize = (uint64)JsonInt(json, sv, "size", 0);
            s.LayoutAlign = (uint64)JsonInt(json, sv, "align", 1);
            var fields = List<FieldDecl>.Create();
            int fv = json.Get(sv, "fields");
            if (fv >= 0 && json.KindOf(fv) == JsonKind.Array)
            {
                foreach (var f in json.Nodes.Get(fv).Items)
                {
                    if (json.KindOf(f) != JsonKind.Object)
                        continue;
                    string fname = JsonString(json, f, "name", "");
                    var type = b.MakeType(JsonString(json, f, "type", ""), "struct " + s.Name + "." + fname);
                    if (!type.IsNull())
                        fields.Add(FieldDecl { Loc = b.Loc, Name = fname, Type = type, Offset = JsonInt(json, f, "offset", 0) });
                }
            }
            s.Fields = fields.ToArray();
            unit.Structs.Add(s);
        }
    }

    int enums = json.Get(root, "enums");
    if (enums >= 0 && json.KindOf(enums) == JsonKind.Array)
    {
        foreach (var ev in json.Nodes.Get(enums).Items)
        {
            if (json.KindOf(ev) != JsonKind.Object)
                continue;
            var e = EnumDecl { Loc = b.Loc, Name = JsonString(json, ev, "name", "") };
            e.Base = b.MakeType(JsonString(json, ev, "base", ""), "enum " + e.Name);
            var members = List<EnumMember>.Create();
            int mv = json.Get(ev, "members");
            if (mv >= 0 && json.KindOf(mv) == JsonKind.Array)
            {
                foreach (var m in json.Nodes.Get(mv).Items)
                {
                    if (json.KindOf(m) != JsonKind.Object)
                        continue;
                    var member = EnumMember { Loc = b.Loc, Name = JsonString(json, m, "name", "") };
                    bool negative = false;
                    uint64 magnitude = 0;
                    if (JsonInteger(json, m, "value", ref negative, ref magnitude))
                        member.Value = b.MakeInteger(negative, magnitude);
                    members.Add(member);
                }
            }
            e.Members = members.ToArray();
            if (!e.Base.IsNull())
                unit.Enums.Add(e);
        }
    }

    int consts = json.Get(root, "constants");
    if (consts >= 0 && json.KindOf(consts) == JsonKind.Array)
    {
        foreach (var cv in json.Nodes.Get(consts).Items)
        {
            if (json.KindOf(cv) != JsonKind.Object)
                continue;
            var c = ConstDecl { Loc = b.Loc, Name = JsonString(json, cv, "name", "") };
            string typeName = JsonString(json, cv, "type", "");
            c.Type = b.MakeType(typeName, "constant " + c.Name);
            bool negative = false;
            uint64 magnitude = 0;
            int valueNode = json.Get(cv, "value");
            if (typeName == "string")
            {
                c.Init = tree.AddStringLit(b.Loc, StringLitExpr { Value = JsonString(json, cv, "value", "") });
            }
            else if (typeName == "float64" || typeName == "float32")
            {
                double number = 0.0;
                if (valueNode >= 0)
                {
                    var parsedNumber = json.Text(valueNode).ParseDouble();
                    if (parsedNumber is double dv)
                        number = dv;
                }
                c.Init = tree.AddFloatLit(b.Loc, FloatLitExpr { Value = number });
            }
            else if (JsonInteger(json, cv, "value", ref negative, ref magnitude))
            {
                c.Init = b.MakeInteger(negative, magnitude);
            }
            if (!c.Type.IsNull() && !c.Init.IsNull())
                unit.Consts.Add(c);
        }
    }

    int functions = json.Get(root, "functions");
    if (functions >= 0 && json.KindOf(functions) == JsonKind.Array)
    {
        foreach (var fnode in json.Nodes.Get(functions).Items)
        {
            if (json.KindOf(fnode) != JsonKind.Object)
                continue;
            var f = FuncDecl { Loc = b.Loc, Name = JsonString(json, fnode, "name", ""), IsExtern = true, Owner = -1 };
            f.TypeParams = new string[0];
            f.Constraints = new Constraint[0];
            f.IsVariadic = JsonBool(json, fnode, "variadic");
            f.Symbol = JsonString(json, fnode, "symbol", "");
            f.RetCString = JsonBool(json, fnode, "retCString");
            f.RetOut = JsonBool(json, fnode, "retOut");
            f.Ret = b.MakeType(JsonString(json, fnode, "returns", "void"), "function " + f.Name);
            bool ok = !f.Ret.IsNull();
            var ps = List<Param>.Create();
            int pv = json.Get(fnode, "params");
            if (pv >= 0 && json.KindOf(pv) == JsonKind.Array)
            {
                foreach (var pnode in json.Nodes.Get(pv).Items)
                {
                    if (json.KindOf(pnode) != JsonKind.Object)
                        continue;
                    var p = Param { Loc = b.Loc, Name = JsonString(json, pnode, "name", "") };
                    string refText = JsonString(json, pnode, "ref", "none");
                    p.Ref = refText == "ref" ? RefKind.Ref : (refText == "constref" ? RefKind.ConstRef : RefKind.None);
                    p.Nullable = JsonBool(json, pnode, "nullable");
                    p.CString = JsonBool(json, pnode, "cstring");
                    p.Type = b.MakeType(JsonString(json, pnode, "type", ""), "function " + f.Name + ", parameter " + p.Name);
                    if (p.Type.IsNull())
                        ok = false;
                    ps.Add(p);
                }
            }
            f.Params = ps.ToArray();
            if (ok)
                unit.Funcs.Add(f);
        }
    }

    if (b.Failed[0] != 0)
        return error(ffiPath + ": the FFI file contains invalid entries (delete it to regenerate it)");
    return unit;
}
