// Structs: layout, fields, methods, initializers and the per-type reference counting (the struct parts of CodeGen.cpp,
// CodeGenExpr.cpp and CodeGenRuntime.cpp).

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

struct FieldInfo
{
    string Name;
    int Type;
    int Index;        // index in the LLVM struct
    bool IsPrivate;
}

struct StructInfo
{
    int Entry;                        // index in Compiler.Structs
    string Name;                      // including type arguments
    int Type;
    Dictionary<string, int> Env;
    int Base;                         // base struct type, 0 = none
    FieldInfo[] Fields;               // own fields only
    bool LayoutInProgress;
    string IrName;                    // %"Name"
}

// A function that a call may refer to: the function and, for methods, the struct it belongs to.
struct Candidate
{
    int Entry;                        // index in Compiler.Funcs
    int Owner;                        // struct type, 0 for free functions
}

struct FieldPath
{
    bool Found;
    int[] Indices;
    int Type;
    bool IsPrivate;
    int Owner;
}

StructInfo GetStructInfo(Compiler cg, int structType)
{
    return cg.StructInfos.Get(cg.Types.Decl(structType));
}

string StructIrName(Compiler cg, int t)
{
    var si = GetStructInfo(cg, t);
    if (si.LayoutInProgress)
        Fail(cg, cg.Structs.Get(si.Entry).Decl.Loc, "struct '" + si.Name + "' contains itself by value");
    return si.IrName;
}

// ---------------------------------------------------------------------------
// The struct type
// ---------------------------------------------------------------------------

int GetStructType(Compiler cg, int entry, int[] args, SourceLoc loc)
{
    var types = cg.Types;
    var se = cg.Structs.Get(entry);
    var decl = se.Decl;
    if (args.Length != decl.TypeParams.Length)
        Fail(cg, loc, "struct '" + decl.Name + "' expects " + decl.TypeParams.Length.ToString() + " type argument(s), got " + args.Length.ToString());
    if (decl.TypeParams.Length > 0)
        Fail(cg, loc, "cshc does not support generic structs yet ('" + decl.Name + "')");
    if (decl.ExplicitLayout)
        Fail(cg, decl.Loc, "cshc does not support imported C structs yet ('" + decl.Name + "')");

    string key = Qualified(cg, se.File, decl.Name);
    var existing = cg.StructTypes.TryGet(key);
    if (existing is int found)
        return found;

    int t = types.Add(TypeKind.Struct, key, 0, false);
    var info = StructInfo { Entry = entry, Name = key, Type = t, IrName = "%\"" + key + "\"" };
    info.Env = Dictionary<string, int>.Create();
    cg.StructInfos.Add(info);
    int index = cg.StructInfos.Count() - 1;
    var ti = types.Info(t);
    ti.Decl = index;
    types.SetInfo(t, ti);
    cg.StructTypes.Set(key, t);

    LayoutStruct(cg, index);

    // The methods of a struct of the program are always generated.
    if (!cg.Files.Get(se.File).IsPrelude)
    {
        var si = cg.StructInfos.Get(index);
        foreach (var m in se.Methods)
        {
            if (cg.Funcs.Get(m).Decl.TypeParams.Length > 0)
                continue;
            UseFunction(cg, GetFuncInstance(cg, m, t, si.Env, new int[0], cg.Funcs.Get(m).Decl.Loc));
        }
    }
    return t;
}

void LayoutStruct(Compiler cg, int index)
{
    var types = cg.Types;
    var si = cg.StructInfos.Get(index);
    var se = cg.Structs.Get(si.Entry);
    var decl = se.Decl;
    si.LayoutInProgress = true;
    cg.StructInfos.Set(index, si);

    var elems = List<string>.Create();
    for (var i = 0; i < decl.Bases.Length; i += 1)
    {
        int b = ResolveType(cg, decl.Bases[i].Id, se.File, si.Env);
        var bnode = cg.Tree.GetType(decl.Bases[i]);
        if (types.IsStruct(b))
        {
            if (i != 0)
                Fail(cg, bnode.Loc, "the base struct must be listed first");
            if (GetStructInfo(cg, b).LayoutInProgress)
                Fail(cg, bnode.Loc, "cyclic struct inheritance");
            si.Base = b;
        }
        else
        {
            Fail(cg, bnode.Loc, "'" + types.Name(b) + "' is neither a struct nor an interface");
        }
    }
    if (si.Base != 0)
        elems.Add(LlvmType(cg, si.Base));

    var fields = List<FieldInfo>.Create();
    foreach (var f in decl.Fields)
    {
        int ft = ResolveValueType(cg, f.Type.Id, se.File, si.Env);
        if (types.IsVoid(ft))
            Fail(cg, f.Loc, "field '" + f.Name + "' cannot have type 'void'");
        for (var k = 0; k < fields.Count(); k += 1)
            if (fields.Get(k).Name == f.Name)
                Fail(cg, f.Loc, "field '" + f.Name + "' is declared twice");
        if (si.Base != 0)
        {
            var inherited = FindField(cg, si.Base, f.Name);
            if (inherited.Found)
                Fail(cg, f.Loc, "field '" + f.Name + "' hides an inherited field");
        }
        fields.Add(FieldInfo { Name = f.Name, Type = ft, Index = elems.Count(), IsPrivate = f.Name.Length > 0 && f.Name[0] == '_' });
        elems.Add(LlvmType(cg, ft));
    }
    si.Fields = fields.ToArray();
    si.LayoutInProgress = false;
    cg.StructInfos.Set(index, si);

    var body = StringBuilder.Create();
    for (var i = 0; i < elems.Count(); i += 1)
    {
        if (i > 0)
            body.Append(", ");
        body.Append(elems.Get(i));
    }
    cg.Ir.Globals.Append(si.IrName + " = type { " + body.ToString() + " }\n");
}

bool StructNeedsArc(Compiler cg, int t)
{
    var si = GetStructInfo(cg, t);
    if (si.LayoutInProgress)
        return false;
    if (si.Base != 0 && NeedsArc(cg, si.Base))
        return true;
    foreach (var f in si.Fields)
        if (NeedsArc(cg, f.Type))
            return true;
    return false;
}

// Finds a field of a struct or of its base structs; the path lists the indices for getelementptr/extractvalue.
FieldPath FindField(Compiler cg, int structType, string name)
{
    var si = GetStructInfo(cg, structType);
    foreach (var f in si.Fields)
    {
        if (f.Name == name)
            return FieldPath { Found = true, Indices = new int[] { f.Index }, Type = f.Type, IsPrivate = f.IsPrivate, Owner = structType };
    }
    if (si.Base != 0)
    {
        var inner = FindField(cg, si.Base, name);
        if (inner.Found)
        {
            var indices = new int[inner.Indices.Length + 1];
            indices[0] = 0;
            for (var i = 0; i < inner.Indices.Length; i += 1)
                indices[i + 1] = inner.Indices[i];
            inner.Indices = indices;
            return inner;
        }
    }
    return FieldPath { };
}

// True if 'ancestor' is 'derived' or one of its base structs (path: the indices of the embedded base).
bool StructIsAncestor(Compiler cg, int ancestor, int derived, ref int[] path)
{
    var indices = List<int>.Create();
    int t = derived;
    while (t != 0 && cg.Types.IsStruct(t))
    {
        if (t == ancestor)
        {
            path = indices.ToArray();
            return true;
        }
        indices.Add(0);
        t = GetStructInfo(cg, t).Base;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Methods
// ---------------------------------------------------------------------------

// The methods with the given name of a struct; if it has none, those of its base struct.
Candidate[] MethodCandidates(Compiler cg, int structType, string name)
{
    int t = structType;
    while (t != 0 && cg.Types.IsStruct(t))
    {
        var si = GetStructInfo(cg, t);
        var se = cg.Structs.Get(si.Entry);
        var found = List<Candidate>.Create();
        foreach (var m in se.Methods)
            if (cg.Funcs.Get(m).Decl.Name == name)
                found.Add(Candidate { Entry = m, Owner = t });
        if (found.Count() > 0)
            return found.ToArray();
        t = si.Base;
    }
    return new Candidate[0];
}

// The struct the current function is a method of (0 for free functions).
int CurrentOwner(Compiler cg)
{
    return cg.Instances.Get(cg.Fn[0].Func).Owner;
}

Value ThisValue(Compiler cg, SourceLoc loc)
{
    if (cg.Fn[0].ThisSlot == null || cg.Fn[0].ThisSlot.Length == 0)
        Fail(cg, loc, "'this' is not available in a static context");
    return Lvalue(CurrentOwner(cg), cg.Ir.Load("ptr", cg.Fn[0].ThisSlot), false);
}

// ---------------------------------------------------------------------------
// Fields and initializers
// ---------------------------------------------------------------------------

string IndexList(int[] indices)
{
    var sb = StringBuilder.Create();
    for (var i = 0; i < indices.Length; i += 1)
    {
        if (i > 0)
            sb.Append(", ");
        sb.Append(indices[i].ToString());
    }
    return sb.ToString();
}

Value FieldAccess(Compiler cg, Value obj, string name, SourceLoc loc)
{
    var ir = cg.Ir;
    var p = FindField(cg, obj.Type, name);
    if (!p.Found)
        Fail(cg, loc, "struct '" + cg.Types.Name(obj.Type) + "' has no field '" + name + "'");
    if (p.IsPrivate && CurrentOwner(cg) != p.Owner)
        Fail(cg, loc, "field '" + name + "' is private to '" + cg.Types.Name(p.Owner) + "'");

    if (obj.IsLValue)
    {
        var sb = StringBuilder.Create();
        sb.Append("i32 0");
        foreach (var i in p.Indices)
            sb.Append(", i32 " + i.ToString());
        string addr = ir.Gep(LlvmType(cg, obj.Type), obj.V, sb.ToString());
        return Lvalue(p.Type, addr, obj.IsConst);
    }
    HoldTemp(cg, obj);
    string value = ir.ExtractValue(LlvmType(cg, obj.Type), obj.V, IndexList(p.Indices));
    return Rvalue(p.Type, value, false);
}

// Type { A = 1, B = 2 }
Value EmitStructInit(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetStructInit(e);
    int t = DeclTypeOf(cg, n.Type);
    if (!types.IsStruct(t))
        Fail(cg, e.Loc, "'" + types.Name(t) + "' is not a struct, initializers are only available for structs");

    string ty = LlvmType(cg, t);
    string agg = "zeroinitializer";
    var seen = HashSet<string>.Create();
    foreach (var f in n.Fields)
    {
        var p = FindField(cg, t, f.Name);
        if (!p.Found)
            Fail(cg, f.Loc, "struct '" + types.Name(t) + "' has no field '" + f.Name + "'");
        if (p.IsPrivate && CurrentOwner(cg) != p.Owner)
            Fail(cg, f.Loc, "field '" + f.Name + "' is private to '" + types.Name(p.Owner) + "'");
        if (!seen.Add(f.Name))
            Fail(cg, f.Loc, "field '" + f.Name + "' is initialized twice");
        Value v = ConvertValue(cg, EmitRValue(cg, f.Value), p.Type, f.Value.Loc);
        agg = ir.InsertValue(ty, agg, LlvmType(cg, p.Type), Consume(cg, v), IndexList(p.Indices));
    }
    return Rvalue(t, agg, NeedsArc(cg, t));
}

// new T(): the zero value of a struct.
Value EmitNewObject(Compiler cg, Expr e)
{
    var types = cg.Types;
    var n = cg.Tree.GetNewObject(e);
    int t = DeclTypeOf(cg, n.Type);
    if (!types.IsStruct(t))
        Fail(cg, e.Loc, "'new' can only create structs and arrays, not '" + types.Name(t) + "'");
    return Rvalue(t, "zeroinitializer", false);
}

// obj.Name, Type.Name
Value EmitMember(Compiler cg, Expr e)
{
    var types = cg.Types;
    var m = cg.Tree.GetMember(e);
    if (m.TypeArgs.Length > 0)
        Fail(cg, e.Loc, "cshc does not support generic members yet");
    if (m.ViaArrow)
        Fail(cg, e.Loc, "cshc does not support pointers yet");

    // A name that is not a variable may be a type or a namespace.
    string dotted = DottedName(cg, m.Object);
    if (dotted.Length > 0 && !IsLocalName(cg, dotted.Split('.')[0]))
    {
        int prim = PrimitiveType(cg, dotted);
        if (prim != 0)
        {
            var constant = Value { };
            if (EmitBuiltinStaticMember(cg, prim, m.Name, ref constant))
                return constant;
            Fail(cg, e.Loc, "type '" + dotted + "' has no member '" + m.Name + "'");
        }
        var entry = TypeDeclEntry { };
        if (CurrentOwner(cg) == 0 || FindField(cg, CurrentOwner(cg), dotted.Split('.')[0]).Found == false)
        {
            if (LookupTypeDecl(cg, cg.Fn[0].File, dotted, ref entry) || IsNamespace(cg, cg.Fn[0].File, dotted))
            {
                int c = LookupConst(cg, cg.Fn[0].File, dotted + "." + m.Name);
                if (c >= 0)
                    return EmitConst(cg, c, e.Loc);
                Fail(cg, e.Loc, "cshc does not support static members yet ('" + dotted + "." + m.Name + "')");
            }
        }
    }

    Value obj = EmitExpr(cg, m.Object);
    int t = obj.Type;
    if (types.IsStruct(t))
        return FieldAccess(cg, obj, m.Name, e.Loc);
    if ((types.IsString(t) || types.IsArray(t)) && m.Name == "Length")
    {
        Value o = ToRValue(cg, obj);
        HoldTemp(cg, o);
        string len = cg.Ir.Call("i64", "@__cs_len", "ptr " + o.V);
        return Rvalue(types.I32, cg.Ir.Cast("trunc", "i64", len, "i32"), false);
    }
    Fail(cg, e.Loc, "type '" + types.Name(t) + "' has no member '" + m.Name + "'");
    return obj;
}

// ---------------------------------------------------------------------------
// Reference counting of structs: one helper function per type
// ---------------------------------------------------------------------------

// Name of the retain/release helper of a struct type; the helper is written the first time it is needed.
string StructHelper(Compiler cg, int t, bool isRetain)
{
    var types = cg.Types;
    var ir = cg.Ir;
    string name = "@\"" + (isRetain ? "__retain." : "__release.") + types.Name(t) + "\"";
    if (!ir.Declared.Add(name))
        return name;
    string ty = LlvmType(cg, t);
    var sb = StringBuilder.Create();
    sb.Append("define internal void " + name + "(" + ty + " %v) {\nentry:\n");
    var si = GetStructInfo(cg, t);
    int n = 0;
    if (si.Base != 0 && NeedsArc(cg, si.Base))
    {
        sb.Append(MemberHelperCall(cg, si.Base, 0, n, isRetain, ty));
        n += 1;
    }
    foreach (var f in si.Fields)
    {
        if (NeedsArc(cg, f.Type))
        {
            sb.Append(MemberHelperCall(cg, f.Type, f.Index, n, isRetain, ty));
            n += 1;
        }
    }
    sb.Append("  ret void\n}\n\n");
    ir.AppendHelper(sb.ToString());
    return name;
}

// "%m<n> = extractvalue ...; call retain/release(%m<n>)" for one member.
string MemberHelperCall(Compiler cg, int memberType, int index, int n, bool isRetain, string structIr)
{
    string reg = "%m" + n.ToString();
    string callee = isRetain ? RetainFunction(cg, memberType) : ReleaseFunction(cg, memberType);
    string call = "call void " + callee + "(" + LlvmType(cg, memberType) + " " + reg + ")";
    return "  " + reg + " = extractvalue " + structIr + " %v, " + index.ToString() + "\n  " + call + "\n";
}

// int.MaxValue, float.Epsilon, ...: constants of the built-in number types. Returns false if there is no such member.
bool EmitBuiltinStaticMember(Compiler cg, int type, string member, ref Value result)
{
    var types = cg.Types;
    if (types.IsIntegral(type))
    {
        int bits = types.Bits(type);
        bool isSigned = types.IsInt(type) && types.IsSigned(type);
        int64 maxValue = 0;
        int64 minValue = 0;
        if (isSigned)
        {
            maxValue = bits == 64 ? 9223372036854775807 : ((int64)1 << (bits - 1)) - 1;
            minValue = -maxValue - 1;
        }
        else
        {
            maxValue = bits == 64 ? -1 : ((int64)1 << bits) - 1;
        }
        if (member == "MaxValue")
        {
            result = ConstInt(cg, type, maxValue);
            return true;
        }
        if (member == "MinValue")
        {
            result = ConstInt(cg, type, minValue);
            return true;
        }
        return false;
    }
    if (types.IsFloat(type))
    {
        bool is32 = types.Bits(type) == 32;
        if (member == "MaxValue" || member == "MinValue")
        {
            double big = is32 ? 3.4028234663852886e38 : 1.7976931348623157e308;
            result = Rvalue(type, FloatConstant(cg, type, member == "MaxValue" ? big : -big), false);
            return true;
        }
        if (member == "Epsilon")
        {
            result = Rvalue(type, FloatConstant(cg, type, is32 ? 1.1920928955078125e-7 : 2.220446049250313e-16), false);
            return true;
        }
        // NaN and the infinities are written as the bits of a double (a float constant has to be exactly representable)
        if (member == "NaN")
        {
            result = Rvalue(type, "0x7FF8000000000000", false);
            return true;
        }
        if (member == "PositiveInfinity")
        {
            result = Rvalue(type, "0x7FF0000000000000", false);
            return true;
        }
        if (member == "NegativeInfinity")
        {
            result = Rvalue(type, "0xFFF0000000000000", false);
            return true;
        }
    }
    return false;
}
