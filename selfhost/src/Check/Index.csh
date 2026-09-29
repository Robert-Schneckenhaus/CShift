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
}

// Records a use of a name (only in the 'check'/'query' mode, and not while the result type of a lambda is inferred).
void IndexAt(Compiler cg, SourceLoc at, int length, SourceLoc def, string hover)
{
    if (!cg.St[0].Indexing || cg.St[0].Muted || at.Line <= 0 || length <= 0)
        return;
    cg.Index.Add(IndexEntry { At = at, Length = length, Def = def, Hover = hover });
}

// The last declared variable is declared at 'loc' (a parameter if isParam).
void NoteVar(Compiler cg, SourceLoc loc, bool isParam)
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
void NoteDeclared(Compiler cg, SourceLoc nameLoc, SourceLoc fallback, bool isParam, TypeRef type, RefKind refKind)
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
string HoverType(Compiler cg, int t)
{
    return cg.Types.IsUnknown(t) ? "?" : cg.Types.Name(t);
}

// A local variable, parameter or pattern variable.
void IndexLocal(Compiler cg, SourceLoc at, string name)
{
    int i = FindLocal(cg, name);
    if (i < 0)
        return;
    var v = cg.Fn[0].Vars.Get(i);
    string kind = v.IsConstant ? "const " : v.IsParam ? "(parameter) " + v.RefText : "";
    string type = cg.Types.IsUnknown(v.Type) && v.TypeText != null && v.TypeText.Length > 0 ? v.TypeText : HoverType(cg, v.Type);
    IndexAt(cg, at, name.Length, v.Loc, kind + type + " " + name);
}

// A field of a struct type (its own or an inherited one).
void IndexField(Compiler cg, SourceLoc at, int structType, string name)
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
                IndexAt(cg, at, name.Length, f.Loc, HoverType(cg, p.Type) + " " + si.Name + "." + name);
                return;
            }
        }
        s = si.Base;
    }
}

void IndexConst(Compiler cg, SourceLoc at, int length, int c)
{
    var entry = cg.Consts.Get(c);
    ConstVal v = ConstEvalDecl(cg, c);
    string value = v.Kind == ConstKind.String ? "\"" + ConstToText(cg, v) + "\"" :
                   v.Kind == ConstKind.Slice || v.Kind == ConstKind.Unknown ? "" : ConstToText(cg, v);
    IndexAt(cg, at, length, entry.Decl.Loc, "const " + HoverType(cg, v.Type) + " " + entry.Decl.Name + (value.Length > 0 ? " = " + value : ""));
}

void IndexGlobal(Compiler cg, SourceLoc at, int length, int g)
{
    var entry = cg.Globals.Get(g);
    IndexAt(cg, at, length, entry.Decl.Loc, HoverType(cg, GlobalValue(cg, g).Type) + " " + entry.Name + " (global)");
}

// A call of a function or method instance: its signature.
void IndexFunction(Compiler cg, SourceLoc at, int length, int instance)
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
    IndexAt(cg, at, length, d.NameLoc.Line > 0 ? d.NameLoc : d.Loc, sb.ToString());
}

// A type in a hover; the type as written when it is not known (a generic body is checked with unknown type arguments).
string DeclaredHoverType(Compiler cg, int t, TypeRef written)
{
    if (cg.Types.IsUnknown(t) && !written.IsNull())
        return cg.Tree.TypeToString(written);
    return HoverType(cg, t);
}

// A member that the language provides (the Length of a string, array, slice or Fixed, the Message and Code of an error):
// a hover, nowhere to go. Returns the value.
Value IndexBuiltinMember(Compiler cg, MemberExpr m, int objType, Value v, string suffix)
{
    IndexAt(cg, m.NameLoc, m.Name.Length, SourceLoc { }, HoverType(cg, v.Type) + " " + cg.Types.Name(objType) + "." + m.Name + suffix);
    return v;
}

// A call of a function that the language provides (Console.WriteLine, x.ToString(), ...): its signature as it was
// called, unless an entry was recorded for the name since 'before' (a function of the standard library).
void IndexBuiltinCall(Compiler cg, SourceLoc at, string owner, string method, Arg[] args, Value result, bool isStatic, int before)
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
    }
    sb.Append(')');
    IndexAt(cg, at, method.Length, SourceLoc { }, sb.ToString());
}

// A call that was not resolved (an argument of unknown type, no matching overload): the function if there is only one
// candidate and it is not generic.
void IndexCandidates(Compiler cg, SourceLoc at, int length, Candidate[] cands)
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
int TypeNameLength(Compiler cg, Expr e, string dotted)
{
    if (e.Kind == ExprKind.Name)
        return cg.Tree.GetName(e).Name.Length;
    return 0;
}

// A type name as written (a struct, interface, enum or union of the program or the standard library).
void IndexTypeName(Compiler cg, SourceLoc at, int length, TypeDeclEntry entry, string name)
{
    switch (entry.Kind)
    {
    case DeclKind.Struct:
        IndexAt(cg, at, length, cg.Structs.Get(entry.Index).Decl.Loc, "struct " + name);
        break;
    case DeclKind.Interface:
        IndexAt(cg, at, length, cg.Interfaces.Get(entry.Index).Decl.Loc, "interface " + name);
        break;
    case DeclKind.Enum:
    {
        var d = cg.Enums.Get(entry.Index).Decl;
        IndexAt(cg, at, length, d.Loc, (d.IsError ? "error " : "enum ") + name);
        break;
    }
    default:
        IndexAt(cg, at, length, cg.Unions.Get(entry.Index).Decl.Loc, "union " + name);
        break;
    }
}

void IndexEnumMember(Compiler cg, SourceLoc at, int length, int enumEntry, int enumType, int member)
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
int FindIndexEntry(Compiler cg, int file, int line, int col)
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
