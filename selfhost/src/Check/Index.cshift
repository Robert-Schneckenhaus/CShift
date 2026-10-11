// The symbol index for tooling (docs/semantic-pass.md, step 7): while the checker runs in the 'check'/'query' mode of
// the driver, every name it resolves is recorded with the place of its declaration and a hover text. 'cshiftc query'
// answers a position from it (hover, go to definition); the VS Code extension calls it.

namespace CShift.Check;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;
using CShift.CodeGen;

struct IndexEntry
{
    SourceLoc At;       // where the name is written
    int Length;         // its length in characters
    SourceLoc Def;      // where it is declared (Line 0: nowhere to go, e.g. a builtin)
    string Hover;       // what it is: a declaration-like line, e.g. "int32 Add(int32 a, int32 b)"
    int Type;           // the type of its value (0: none), for the members after a '.'
    bool IsTypeName;    // a type name: after a '.' come its static members (enum members, static methods)
}

// Records a use of a name (only in the 'check'/'query' mode, and not while the result type of a lambda is inferred).
void IndexAt(const ref Compiler cg, SourceLoc at, int length, SourceLoc def, string hover)
{
    IndexAtTyped(cg, at, length, def, hover, 0, false);
}

// ... with the type of the name's value (or the type it names).
void IndexAtTyped(const ref Compiler cg, SourceLoc at, int length, SourceLoc def, string hover, int type, bool isTypeName)
{
    if (!cg.St[0].Indexing || cg.St[0].Muted || at.Line <= 0 || length <= 0)
        return;
    cg.Index.Add(IndexEntry { At = at, Length = length, Def = def, Hover = hover, Type = type, IsTypeName = isTypeName });
}

// The last declared variable is declared at 'loc' (a parameter if isParam).
void NoteVar(const ref Compiler cg, SourceLoc loc, bool isParam)
{
    var vars = cg.Fn[0].Vars;
    if (vars.Count() == 0)
        return;
    var v = vars.Get(vars.Count() - 1);
    v.Loc = loc;
    v.IsParam = isParam;
    vars.Set(vars.Count() - 1, v);
}

// The last declared variable is declared at 'nameLoc' (where its name is written; 'fallback' if that is not known),
// with its type as written; the declaration itself is indexed (a hover on the name where it is declared).
void NoteDeclared(const ref Compiler cg, SourceLoc nameLoc, SourceLoc fallback, bool isParam, TypeRef type, RefKind refKind)
{
    var vars = cg.Fn[0].Vars;
    if (vars.Count() == 0)
        return;
    var v = vars.Get(vars.Count() - 1);
    v.Loc = nameLoc.Line > 0 ? nameLoc : fallback;
    v.IsParam = isParam;
    v.TypeText = type.IsNull() ? "" : cg.Tree.TypeToString(type);
    v.RefText = refKind == RefKind.Ref ? "ref " : refKind == RefKind.ConstRef ? "const ref " : "";
    vars.Set(vars.Count() - 1, v);
    if (nameLoc.Line > 0)
        IndexLocal(cg, nameLoc, v.Name);
}

// The type as it is shown in a hover.
string HoverType(const ref Compiler cg, int t)
{
    return cg.Types.IsUnknown(t) ? "?" : cg.Types.Name(t);
}

// A local variable, parameter or pattern variable.
void IndexLocal(const ref Compiler cg, SourceLoc at, string name)
{
    if (!cg.St[0].Indexing)
        return;
    int i = FindLocal(cg, name);
    if (i < 0)
        return;
    var v = cg.Fn[0].Vars.Get(i);
    string kind = v.IsConstant ? "const " : v.IsParam ? "(parameter) " + v.RefText : "";
    string type = cg.Types.IsUnknown(v.Type) && v.TypeText != null && v.TypeText.Length > 0 ? v.TypeText : HoverType(cg, v.Type);
    IndexAtTyped(cg, at, name.Length, v.Loc, kind + type + " " + name + (v.IsConstant ? ConstValueHover(cg, v.ConstValue) : ""),
                 v.Type, false);
}

// A field of a struct type (its own or an inherited one).
void IndexField(const ref Compiler cg, SourceLoc at, int structType, string name)
{
    int s = structType;
    while (s != 0 && cg.Types.IsStruct(s))
    {
        var si = GetStructInfo(cg, s);
        foreach (var f in cg.Structs.Get(si.Entry).Decl.Fields)
        {
            if (f.Name == name)
            {
                var p = FindField(cg, structType, name);
                IndexAtTyped(cg, at, name.Length, f.Loc, FieldHover(cg, p.Type, si.Name + "." + name), p.Type, false);
                return;
            }
        }
        s = si.Base;
    }
}

// A field in a hover; one with a function type (Action/Func, a C function pointer) shows as the signature it is
// called with: "uint32 Gl.GlFunctions.CreateShader(uint32) (function pointer field)".
string FieldHover(const ref Compiler cg, int t, string qualified)
{
    var types = cg.Types;
    bool c = types.IsCFunction(t);
    int fn = c ? types.Elem(t) : t;
    if (!types.IsFunction(fn))
        return HoverType(cg, t) + " " + qualified;
    var sb = StringBuilder.Create();
    sb.Append(HoverType(cg, types.Elem(fn)));
    sb.Append(' ');
    sb.Append(qualified);
    sb.Append('(');
    int[] ps = types.Params(fn);
    for (var i = 0; i < ps.Length; i += 1)
    {
        if (i > 0)
            sb.Append(", ");
        sb.Append(HoverType(cg, ps[i]));
    }
    sb.Append(c ? ") (C function pointer field)" : ") (function field)");
    return sb.ToString();
}

void IndexConst(const ref Compiler cg, SourceLoc at, int length, int c)
{
    if (!cg.St[0].Indexing)
        return;
    var entry = cg.Consts.Get(c);
    ConstVal v = ConstEvalDecl(cg, c);
    IndexAtTyped(cg, at, length, entry.Decl.Loc, "const " + HoverType(cg, v.Type) + " " + entry.Decl.Name + ConstValueHover(cg, v),
                 v.Type, false);
}

// The value of a constant in a hover: " = 42", " = \"text\"", or for a longer string (an embedded file) its size and
// its first lines below the declaration; for the bytes of an embedded file their number.
string ConstValueHover(const ref Compiler cg, ConstVal v)
{
    if (v.Kind == ConstKind.Slice && v.Bytes.Length > 0)
        return " // " + v.Bytes.Length.ToString() + " bytes";
    if (v.Kind == ConstKind.Slice || v.Kind == ConstKind.Unknown)
        return "";
    string s = ConstToText(cg, v);
    if (v.Kind != ConstKind.String)
        return " = " + s;
    if (s.Length <= 80 && s.IndexOf('\n') < 0)
        return " = \"" + s + "\"";
    var lines = s.Split('\n');
    int count = lines.Length;
    if (count > 1 && lines[count - 1].Length == 0)
        count -= 1; // the newline at the end of a file
    var sb = StringBuilder.Create();
    sb.Append(" // ");
    sb.Append(s.Length.ToString());
    sb.Append(" bytes, ");
    sb.Append(count.ToString());
    sb.Append(count == 1 ? " line" : " lines");
    int shown = count < 20 ? count : 20;
    for (var i = 0; i < shown; i += 1)
    {
        string line = lines[i].ToString();
        if (line.Length > 0 && line[line.Length - 1] == '\r')
            line = line.Substring(0, line.Length - 1);
        sb.Append('\n');
        sb.Append(line.Length > 120 ? line.Substring(0, 120) + "..." : line);
    }
    if (shown < count)
        sb.Append("\n...");
    return sb.ToString();
}

void IndexGlobal(const ref Compiler cg, SourceLoc at, int length, int g)
{
    var entry = cg.Globals.Get(g);
    int type = GlobalValue(cg, g).Type;
    IndexAtTyped(cg, at, length, entry.Decl.Loc, HoverType(cg, type) + " " + entry.Name + " (global)", type, false);
}

// A call of a function or method instance: its signature.
void IndexFunction(const ref Compiler cg, SourceLoc at, int length, int instance)
{
    if (instance < 0)
        return;
    var fi = cg.Instances.Get(instance);
    if (fi.Entry < 0)
        return;
    var d = cg.Funcs.Get(fi.Entry).Decl;
    var sb = StringBuilder.Create();
    if (d.IsStatic && fi.Owner != 0)
        sb.Append("static ");
    sb.Append(DeclaredHoverType(cg, fi.Ret, d.Ret));
    sb.Append(' ');
    sb.Append(DisplayName(cg, instance));
    sb.Append('(');
    for (var i = 0; i < fi.ParamTypes.Length && i < d.Params.Length; i += 1)
    {
        if (i > 0)
            sb.Append(", ");
        sb.Append(fi.ParamRefs[i] == 1 ? "ref " : fi.ParamRefs[i] == 2 ? "const ref " : "");
        sb.Append(DeclaredHoverType(cg, fi.ParamTypes[i], d.Params[i].Type));
        sb.Append(' ');
        sb.Append(d.Params[i].Name);
    }
    sb.Append(')');
    IndexAtTyped(cg, at, length, d.NameLoc.Line > 0 ? d.NameLoc : d.Loc, sb.ToString(), fi.Ret, false);
}

// A type in a hover; the type as written when it is not known (a generic body is checked with unknown type arguments).
string DeclaredHoverType(const ref Compiler cg, int t, TypeRef written)
{
    if (cg.Types.IsUnknown(t) && !written.IsNull())
        return cg.Tree.TypeToString(written);
    return HoverType(cg, t);
}

// A member that the language provides (the Length of a string, array, slice or Fixed, the Message and Code of an error):
// a hover, nowhere to go. Returns the value.
Value IndexBuiltinMember(const ref Compiler cg, MemberExpr m, int objType, Value v, string suffix)
{
    IndexAtTyped(cg, m.NameLoc, m.Name.Length, SourceLoc { }, HoverType(cg, v.Type) + " " + cg.Types.Name(objType) + "." + m.Name +
                 suffix, v.Type, false);
    return v;
}

// A namespace name as written before '.' (Math.PI, Glfw.glfwInit()); one imported from a C header also says which
// and goes to it.
void IndexNamespace(const ref Compiler cg, Expr e, string name)
{
    if (!cg.St[0].Indexing || e.Kind != ExprKind.Name)
        return;
    var imported = cg.Imported.TryGet(name);
    if (imported is ImportedNamespace ns)
        IndexAt(cg, e.Loc, name.Length, ns.Loc, "namespace " + name + " (imported from \"" + ns.Header + "\")");
    else
        IndexAt(cg, e.Loc, name.Length, SourceLoc { }, "namespace " + name);
}

// A call of a function that the language provides (Console.WriteLine, x.ToString(), ...): its signature as it was
// called, unless an entry was recorded for the name since 'before' (a function of the standard library).
void IndexBuiltinCall(const ref Compiler cg, SourceLoc at, string owner, string method, Arg[] args, Value result, bool isStatic, int before)
{
    if (!cg.St[0].Indexing || IsUnknown(cg, result))
        return;
    for (var i = before; i < cg.Index.Count(); i += 1)
    {
        var e = cg.Index.Get(i);
        if (e.At.File == at.File && e.At.Line == at.Line && e.At.Col == at.Col)
            return;
    }
    var sb = StringBuilder.Create();
    if (isStatic)
        sb.Append("static ");
    sb.Append(HoverType(cg, result.Type));
    sb.Append(' ');
    sb.Append(owner);
    sb.Append('.');
    sb.Append(method);
    sb.Append('(');
    for (var i = 0; i < args.Length; i += 1)
    {
        if (i > 0)
            sb.Append(", ");
        sb.Append(HoverType(cg, args[i].V.Type));
        string paramName = BuiltinParamName(method, i);
        if (paramName.Length > 0)
        {
            sb.Append(' ');
            sb.Append(paramName);
        }
    }
    sb.Append(')');
    IndexAtTyped(cg, at, method.Length, SourceLoc { }, sb.ToString(), result.Type, false);
}

// The name of parameter i of a function the language provides ("" if it has none to show).
string BuiltinParamName(string method, int i)
{
    switch (method)
    {
    case "Write":
    case "WriteLine":
    case "WriteError":
    case "WriteErrorLine":
    case "CopyForThread":
        return i == 0 ? "value" : "";
    case "Exit":
        return i == 0 ? "code" : "";
    case "Panic":
        return i == 0 ? "message" : "";
    case "Allocate":
        return i == 0 ? "size" : "";
    case "Free":
    case "VolatileRead":
        return i == 0 ? "pointer" : "";
    case "VolatileWrite":
        return i == 0 ? "pointer" : i == 1 ? "value" : "";
    case "FromCStr":
        return i == 0 ? "text" : "";
    case "FromBytes":
        return i == 0 ? "bytes" : "";
    case "ToString":
        return i == 0 ? "format" : "";
    case "Substring":
        return i == 0 ? "start" : i == 1 ? "length" : "";
    case "Equals":
    case "CompareTo":
        return i == 0 ? "other" : "";
    default:
        return "";
    }
}

// A call that was not resolved (an argument of unknown type, no matching overload): the function if there is only one
// candidate and it is not generic.
void IndexCandidates(const ref Compiler cg, SourceLoc at, int length, Candidate[] cands)
{
    if (!cg.St[0].Indexing || cands.Length != 1 || at.Line <= 0)
        return;
    var c = cands[0];
    var d = cg.Funcs.Get(c.Entry).Decl;
    if (d.TypeParams.Length > 0 || (c.Owner != 0 && !cg.Types.IsStruct(c.Owner)))
        return;
    var env = c.Owner != 0 ? GetStructInfo(cg, c.Owner).Env : NoEnv();
    IndexFunction(cg, at, length, GetFuncInstance(cg, c.Entry, c.Owner, env, new int[0], d.Loc));
}

// The length of the type name that the expression is ('List<int>': the name without type arguments); 0 for a qualified
// name ('Ns.Type': the expression's place is that of its last '.', not of the name), which is not indexed.
int TypeNameLength(const ref Compiler cg, Expr e, string dotted)
{
    if (e.Kind == ExprKind.Name)
        return cg.Tree.GetName(e).Name.Length;
    return 0;
}

// A type name as written (a struct, interface, enum or union of the program or the standard library).
void IndexTypeName(const ref Compiler cg, SourceLoc at, int length, TypeDeclEntry entry, string name)
{
    switch (entry.Kind)
    {
    case DeclKind.Struct:
    {
        var sd = cg.Structs.Get(entry.Index).Decl;
        int st = sd.TypeParams.Length == 0 ? GetStructType(cg, entry.Index, new int[0], sd.Loc) : 0;
        IndexAtTyped(cg, at, length, sd.Loc, "struct " + name, st, true);
        break;
    }
    case DeclKind.Interface:
        IndexAt(cg, at, length, cg.Interfaces.Get(entry.Index).Decl.Loc, "interface " + name);
        break;
    case DeclKind.Enum:
    {
        var d = cg.Enums.Get(entry.Index).Decl;
        IndexAtTyped(cg, at, length, d.Loc, (d.IsError ? "error " : "enum ") + name, GetEnumType(cg, entry.Index), true);
        break;
    }
    default:
        IndexAt(cg, at, length, cg.Unions.Get(entry.Index).Decl.Loc, "union " + name);
        break;
    }
}

void IndexEnumMember(const ref Compiler cg, SourceLoc at, int length, int enumEntry, int enumType, int member)
{
    var info = GetEnumInfo(cg, enumType);
    var d = cg.Enums.Get(enumEntry).Decl;
    SourceLoc def = d.Loc;
    foreach (var m in d.Members)
    {
        if (m.Name == info.Names[member])
            def = m.Loc;
    }
    IndexAt(cg, at, length, def, cg.Types.Name(enumType) + "." + info.Names[member] + " = " + info.Values[member].ToString());
}

// ---------------------------------------------------------------------------
// The answer of 'cshiftc query'
// ---------------------------------------------------------------------------

// The innermost entry at the position (1-based line and column) of the file, or -1.
int FindIndexEntry(const ref Compiler cg, int file, int line, int col)
{
    int best = -1;
    for (var i = 0; i < cg.Index.Count(); i += 1)
    {
        var e = cg.Index.Get(i);
        if (e.At.File != file || e.At.Line != line || col < e.At.Col || col >= e.At.Col + e.Length)
            continue;
        if (best < 0 || e.Length < cg.Index.Get(best).Length)
            best = i;
    }
    return best;
}

// A JSON string literal.
string JsonString(string s)
{
    var sb = StringBuilder.Create();
    sb.Append('"');
    foreach (var c in s)
    {
        if (c == '"')
            sb.Append("\\\"");
        else if (c == '\\')
            sb.Append("\\\\");
        else if (c == '\n')
            sb.Append("\\n");
        else if (c == '\r')
            sb.Append("\\r");
        else if (c == '\t')
            sb.Append("\\t");
        else if ((int)c < 32)
            sb.Append(" ");
        else
            sb.Append(c);
    }
    sb.Append('"');
    return sb.ToString();
}

// ---------------------------------------------------------------------------
// References, members, outline ('cshiftc query --references / --members / --outline')
// ---------------------------------------------------------------------------

// "file": "...", "line": n, "col": n (empty if the place is not in a file)
string JsonPlace(const ref Compiler cg, Diagnostics diag, SourceLoc at)
{
    if (at.Line <= 0 || at.File < 0 || at.File >= diag.Files.Count() || diag.Files.Get(at.File).StartsWith("<"))
        return "";
    return "\"file\": " + JsonString(Path.GetFullPath(diag.Files.Get(at.File))) + ", \"line\": " + at.Line.ToString() +
           ", \"col\": " + at.Col.ToString();
}

// Every place where the name of entry 'found' is written, the declaration included: the entries with the same
// declaration.
string ReferencesJson(const ref Compiler cg, Diagnostics diag, int found)
{
    var def = cg.Index.Get(found).Def;
    var seen = HashSet<string>.Create();
    var sb = StringBuilder.Create();
    sb.Append("[");
    for (var i = 0; i < cg.Index.Count(); i += 1)
    {
        var e = cg.Index.Get(i);
        if (def.Line <= 0 ? i != found : (e.Def.File != def.File || e.Def.Line != def.Line || e.Def.Col != def.Col))
            continue;
        string place = JsonPlace(cg, diag, e.At);
        if (place.Length == 0 || seen.Contains(place))
            continue;
        seen.Add(place);
        sb.Append(seen.Count() > 1 ? ", " : "");
        sb.Append("{" + place + ", \"length\": " + e.Length.ToString() + "}");
    }
    sb.Append("]");
    return sb.ToString();
}

// One member for completion: {"name": ..., "kind": "field"/"method"/"enumMember"/"property", "detail": ...}.
void AddMember(StringBuilder sb, HashSet<string> seen, string name, string kind, string detail)
{
    if (name.Length == 0 || name[0] == '_' || seen.Contains(name))
        return;
    seen.Add(name);
    sb.Append(seen.Count() > 1 ? ", " : "");
    sb.Append("{\"name\": " + JsonString(name) + ", \"kind\": \"" + kind + "\", \"detail\": " + JsonString(detail) + "}");
}

// A method as it is shown in a completion list: "int32 Add(int32 a, int32 b)".
string MethodDetail(const ref Compiler cg, FuncDecl d)
{
    var sb = StringBuilder.Create();
    if (d.IsStatic)
        sb.Append("static ");
    sb.Append(d.Ret.IsNull() ? "void" : cg.Tree.TypeToString(d.Ret));
    sb.Append(' ');
    sb.Append(d.Name);
    sb.Append('(');
    for (var i = 0; i < d.Params.Length; i += 1)
    {
        if (i > 0)
            sb.Append(", ");
        sb.Append(d.Params[i].Type.IsNull() ? "?" : cg.Tree.TypeToString(d.Params[i].Type));
        sb.Append(' ');
        sb.Append(d.Params[i].Name);
    }
    sb.Append(')');
    return sb.ToString();
}

// What can follow 'x.' when x has type t (or names the type t: its static members): a JSON list.
string MembersJson(const ref Compiler cg, int t, bool isTypeName)
{
    var types = cg.Types;
    var sb = StringBuilder.Create();
    var seen = HashSet<string>.Create();
    sb.Append("[");
    if (t != 0 && !types.IsUnknown(t))
    {
        if (types.IsEnum(t) && isTypeName)
        {
            var info = GetEnumInfo(cg, t);
            for (var i = 0; i < info.Names.Length; i += 1)
                AddMember(sb, seen, info.Names[i], "enumMember", types.Name(t) + "." + info.Names[i] + " = " + info.Values[i].ToString());
        }
        else if (types.IsStruct(t))
        {
            int s = t;
            while (s != 0 && types.IsStruct(s))
            {
                var si = GetStructInfo(cg, s);
                var sd = cg.Structs.Get(si.Entry).Decl;
                if (!isTypeName)
                {
                    foreach (var f in sd.Fields)
                    {
                        var p = FindField(cg, t, f.Name);
                        AddMember(sb, seen, f.Name, "field", HoverType(cg, p.Type) + " " + f.Name);
                    }
                }
                foreach (var m in sd.Methods)
                {
                    if (m.IsStatic == isTypeName)
                        AddMember(sb, seen, m.Name, "method", MethodDetail(cg, m));
                }
                s = si.Base;
            }
        }
        else if (types.Kind(t) == TypeKind.Interface)
        {
            foreach (var m in cg.Interfaces.Get(cg.InterfaceInfos.Get(types.Decl(t)).Entry).Decl.Methods)
                AddMember(sb, seen, m.Name, "method", MethodDetail(cg, m));
        }
        else if (!isTypeName)
        {
            if (types.IsString(t) || types.IsStringSlice(t) || types.IsArray(t) || types.IsSlice(t) || types.IsFixed(t))
                AddMember(sb, seen, "Length", "property", "int32 Length");
            if (types.IsString(t) || types.IsStringSlice(t))
            {
                // the String namespace of the standard library: its functions are methods of strings
                foreach (var key in cg.FuncDecls.Keys())
                {
                    if (!key.StartsWith("String.") || key.IndexOf('.', 7) >= 0)
                        continue;
                    var list = cg.FuncDecls.Get(key);
                    if (list.Count() > 0)
                    {
                        var d = cg.Funcs.Get(list.Get(0)).Decl;
                        AddMember(sb, seen, key.Substring(7).ToString(), "method", MethodDetail(cg, d));
                    }
                }
            }
            AddMember(sb, seen, "ToString", "method", "string ToString()");
        }
    }
    sb.Append("]");
    return sb.ToString();
}

// One symbol of the outline: {"name", "kind", "line", "col", "children": [...]}.
string OutlineSymbol(string name, string kind, SourceLoc loc, string children)
{
    return "{\"name\": " + JsonString(name) + ", \"kind\": \"" + kind + "\", \"line\": " + loc.Line.ToString() + ", \"col\": " +
           loc.Col.ToString() + (children.Length > 0 ? ", \"children\": [" + children + "]" : "") + "}";
}

// The declarations of a file, for the outline of an editor: types with their members, functions, constants, globals.
string OutlineJson(const ref Compiler cg, int file)
{
    var items = List<string>.Create();
    for (var i = 0; i < cg.Structs.Count(); i += 1)
    {
        var se = cg.Structs.Get(i);
        if (se.File != file)
            continue;
        var kids = List<string>.Create();
        foreach (var f in se.Decl.Fields)
            kids.Add(OutlineSymbol(f.Name, "field", f.Loc, ""));
        foreach (var m in se.Decl.Methods)
            kids.Add(OutlineSymbol(m.Name, "method", m.NameLoc.Line > 0 ? m.NameLoc : m.Loc, ""));
        items.Add(OutlineSymbol(se.Decl.Name, "struct", se.Decl.Loc, string.Join(", ", kids.ToArray())));
    }
    for (var i = 0; i < cg.Interfaces.Count(); i += 1)
    {
        var ie = cg.Interfaces.Get(i);
        if (ie.File != file)
            continue;
        var kids = List<string>.Create();
        foreach (var m in ie.Decl.Methods)
            kids.Add(OutlineSymbol(m.Name, "method", m.NameLoc.Line > 0 ? m.NameLoc : m.Loc, ""));
        items.Add(OutlineSymbol(ie.Decl.Name, "interface", ie.Decl.Loc, string.Join(", ", kids.ToArray())));
    }
    for (var i = 0; i < cg.Enums.Count(); i += 1)
    {
        var ee = cg.Enums.Get(i);
        if (ee.File != file)
            continue;
        var kids = List<string>.Create();
        foreach (var m in ee.Decl.Members)
            kids.Add(OutlineSymbol(m.Name, "enumMember", m.Loc, ""));
        items.Add(OutlineSymbol(ee.Decl.Name, "enum", ee.Decl.Loc, string.Join(", ", kids.ToArray())));
    }
    for (var i = 0; i < cg.Unions.Count(); i += 1)
    {
        var ue = cg.Unions.Get(i);
        if (ue.File == file)
            items.Add(OutlineSymbol(ue.Decl.Name, "union", ue.Decl.Loc, ""));
    }
    for (var i = 0; i < cg.Funcs.Count(); i += 1)
    {
        var fe = cg.Funcs.Get(i);
        if (fe.File == file && fe.OwnerStruct == -1 && fe.Decl.Loc.Line > 0)
            items.Add(OutlineSymbol(fe.Decl.Name, "function", fe.Decl.NameLoc.Line > 0 ? fe.Decl.NameLoc : fe.Decl.Loc, ""));
    }
    for (var i = 0; i < cg.Consts.Count(); i += 1)
    {
        var ce = cg.Consts.Get(i);
        if (ce.File == file)
            items.Add(OutlineSymbol(ce.Decl.Name, "constant", ce.Decl.Loc, ""));
    }
    for (var i = 0; i < cg.Globals.Count(); i += 1)
    {
        var ge = cg.Globals.Get(i);
        if (ge.File == file)
            items.Add(OutlineSymbol(ge.Decl.Name, "variable", ge.Decl.Loc, ""));
    }
    return "[" + string.Join(", ", items.ToArray()) + "]";
}
