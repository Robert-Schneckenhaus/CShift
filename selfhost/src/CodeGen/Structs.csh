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
    int[] Interfaces;                 // interface types the struct lists in its base list
    bool LayoutInProgress;
    int LayoutContext;                // ... in this layout context (CgState.LayoutContext)
    bool Opaque;                      // an incomplete C type: only usable through pointers
    string IrName;                    // %"Name"
    bool UnknownBase;                 // the base struct is the unknown type (the checker's instance of a generic struct)
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

StructInfo GetStructInfo(const ref Compiler cg, int structType)
{
    return cg.StructInfos.Get(cg.Types.Decl(structType));
}

string StructIrName(const ref Compiler cg, int t)
{
    var si = GetStructInfo(cg, t);
    if (si.LayoutInProgress && si.LayoutContext == cg.St[0].LayoutContext)
        Fail(cg, cg.Structs.Get(si.Entry).Decl.Loc, "struct '" + si.Name + "' contains itself by value");
    return si.IrName;
}

// ---------------------------------------------------------------------------
// The struct type
// ---------------------------------------------------------------------------

int GetStructType(const ref Compiler cg, int entry, int[] args, SourceLoc loc)
{
    var types = cg.Types;
    var se = cg.Structs.Get(entry);
    var decl = se.Decl;
    if (args.Length != decl.TypeParams.Length)
        return RecoverType(cg, loc, "struct '" + decl.Name + "' expects " + decl.TypeParams.Length.ToString() + " type argument(s), got " + args.Length.ToString());
    if (HasUnknownType(cg, args))
        return types.Unknown; // List<Foo> with an unknown Foo (reported where it is written)

    foreach (var a in args)
    {
        if (IsInterfaceType(cg, a))
            return RecoverType(cg, loc, "an interface cannot be a type argument ('" + cg.Types.Name(a) + "'); an interface is only a 'ref'/'const ref' parameter");
    }
    string key = Qualified(cg, se.File, decl.Name) + TypeArgsSuffix(cg, args);
    var existing = cg.StructTypes.TryGet(key);
    if (existing is int found)
        return found;

    int t = CreateStructType(cg, entry, args, key);
    int index = types.Info(t).Decl;
    CheckConstraints(cg, decl.Constraints, cg.StructInfos.Get(index).Env, se.File, decl.Loc);
    if ((key.StartsWith("System.Mutex<") || key.StartsWith("System.MutexGuard<")) && cg.Files.Get(se.File).IsPrelude &&
        !IsThreadTransferable(cg, args[0]))
        Fail(cg, loc, "Mutex<T> needs a value that can be copied between threads (numbers, strings, SharedPtr<T> of thread-safe " +
                          "values, and Optional<T>/Error<T>/structs of them), not '" + types.Name(args[0]) + "'");
    cg.PendingVerify.Add(t);

    // The methods of a struct of the program are always generated.
    if (!cg.Files.Get(se.File).IsPrelude)
        cg.PendingMethods.Add(t);
    InstantiateStructMethods(cg);
    return t;
}

// The instance of a generic struct that the checker checks its methods with: every type parameter is the unknown type
// (docs/semantic-pass.md). It has fields (with unknown types where they use a type parameter), but it is never verified
// against its interfaces or constraints and its methods are never generated.
int GetCheckingStructType(const ref Compiler cg, int entry)
{
    var se = cg.Structs.Get(entry);
    var args = new int[se.Decl.TypeParams.Length];
    for (var i = 0; i < args.Length; i += 1)
        args[i] = cg.Types.Unknown;
    string key = Qualified(cg, se.File, se.Decl.Name) + TypeArgsSuffix(cg, args);
    var existing = cg.StructTypes.TryGet(key);
    if (existing is int found)
        return found;
    return CreateStructType(cg, entry, args, key);
}

// A new struct type for the arguments: its information and layout.
int CreateStructType(const ref Compiler cg, int entry, int[] args, string key)
{
    var types = cg.Types;
    var decl = cg.Structs.Get(entry).Decl;
    int t = types.Add(TypeKind.Struct, key, 0, false);
    var info = StructInfo { Entry = entry, Name = key, Type = t, IrName = "%\"" + key + "\"" };
    info.Env = Dictionary<string, int>.Create();
    info.Interfaces = new int[0];
    for (var i = 0; i < args.Length; i += 1)
        info.Env.Set(decl.TypeParams[i], args[i]);
    cg.StructInfos.Add(info);
    int index = cg.StructInfos.Count() - 1;
    var ti = types.Info(t);
    ti.Decl = index;
    types.SetInfo(t, ti);
    cg.StructTypes.Set(key, t);

    cg.St[0].LayoutDepth += 1;
    LayoutStruct(cg, index);
    cg.St[0].LayoutDepth -= 1;
    return t;
}

// Declaring a method needs the types of its parameters and result, so the methods wait until no struct layout is
// running: while the layout of 'Session' runs (it has a field of type 'Stack', whose method takes a 'Session'), the
// method's signature must not ask for the unfinished 'Session' - that is not a cycle, only the fields decide that.
void InstantiateStructMethods(const ref Compiler cg)
{
    if (cg.St[0].LayoutDepth > 0 || cg.St[0].InstantiatingMethods)
        return;
    cg.St[0].InstantiatingMethods = true;
    // the list grows while this runs (a signature can bring in new struct types)
    for (var i = 0; i < cg.PendingMethods.Count(); i += 1)
    {
        int t = cg.PendingMethods.Get(i);
        var si = cg.StructInfos.Get(cg.Types.Info(t).Decl);
        foreach (var m in cg.Structs.Get(si.Entry).Methods)
        {
            if (cg.Funcs.Get(m).Decl.TypeParams.Length > 0)
                continue;
            UseFunction(cg, GetFuncInstance(cg, m, t, si.Env, new int[0], cg.Funcs.Get(m).Decl.Loc));
        }
    }
    cg.PendingMethods.Clear();
    cg.St[0].InstantiatingMethods = false;
}

void LayoutStruct(const ref Compiler cg, int index)
{
    var types = cg.Types;
    var si = cg.StructInfos.Get(index);
    var se = cg.Structs.Get(si.Entry);
    var decl = se.Decl;
    si.LayoutInProgress = true;
    si.LayoutContext = cg.St[0].LayoutContext;
    cg.StructInfos.Set(index, si);
    if (decl.ExplicitLayout)
    {
        LayoutExplicitStruct(cg, index);
        return;
    }

    var elems = List<string>.Create();
    for (var i = 0; i < decl.Bases.Length; i += 1)
    {
        int b = ResolveType(cg, decl.Bases[i].Id, se.File, si.Env);
        var bnode = cg.Tree.GetType(decl.Bases[i]);
        if (types.IsStruct(b))
        {
            if (i != 0)
                Recover(cg, bnode.Loc, "the base struct must be listed first");
            if (GetStructInfo(cg, b).LayoutInProgress)
            {
                Recover(cg, bnode.Loc, "cyclic struct inheritance");
                continue;
            }
            si.Base = b;
        }
        else if (types.Kind(b) == TypeKind.Interface)
        {
            var grown = new int[si.Interfaces.Length + 1];
            for (var k = 0; k < si.Interfaces.Length; k += 1)
                grown[k] = si.Interfaces[k];
            grown[si.Interfaces.Length] = b;
            si.Interfaces = grown;
        }
        else if (types.IsUnknown(b))
        {
            si.UnknownBase = true;
        }
        else
        {
            Recover(cg, bnode.Loc, "'" + types.Name(b) + "' is neither a struct nor an interface");
        }
    }
    if (si.Base != 0)
        elems.Add(LlvmType(cg, si.Base));

    var fields = List<FieldInfo>.Create();
    foreach (var f in decl.Fields)
    {
        // an array or a pointer is a new layout context: a struct whose layout is still running further out is not
        // contained by value through it ('struct Node { Dictionary<string, Node> Fields; }' reaches Node's entries
        // through the dictionary's array)
        var fnode = cg.Tree.GetType(f.Type);
        int outerContext = cg.St[0].LayoutContext;
        if (fnode.Kind == TypeRefKind.Array || fnode.Kind == TypeRefKind.Pointer)
        {
            cg.St[0].LayoutContexts += 1;
            cg.St[0].LayoutContext = cg.St[0].LayoutContexts;
        }
        int ft = ResolveValueType(cg, f.Type.Id, se.File, si.Env);
        cg.St[0].LayoutContext = outerContext;
        if (types.IsVoid(ft))
            ft = RecoverType(cg, f.Loc, "field '" + f.Name + "' cannot have type 'void'");
        // a field declared twice, or hiding an inherited one, is reported and left out
        bool twice = false;
        for (var k = 0; k < fields.Count(); k += 1)
        {
            if (fields.Get(k).Name == f.Name)
                twice = true;
        }
        if (twice)
        {
            Recover(cg, f.Loc, "field '" + f.Name + "' is declared twice");
            continue;
        }
        if (si.Base != 0 && FindField(cg, si.Base, f.Name).Found)
        {
            Recover(cg, f.Loc, "field '" + f.Name + "' hides an inherited field");
            continue;
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

bool StructNeedsArc(const ref Compiler cg, int t)
{
    var si = GetStructInfo(cg, t);
    if (si.LayoutInProgress)
        return false;
    if (si.Base != 0 && NeedsArc(cg, si.Base))
        return true;
    foreach (var f in si.Fields)
    {
        if (NeedsArc(cg, f.Type))
            return true;
    }
    return false;
}

// Finds a field of a struct or of its base structs; the path lists the indices for getelementptr/extractvalue.
FieldPath FindField(const ref Compiler cg, int structType, string name)
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
bool StructIsAncestor(const ref Compiler cg, int ancestor, int derived, ref int[] path)
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
Candidate[] MethodCandidates(const ref Compiler cg, int structType, string name)
{
    int t = structType;
    while (t != 0 && cg.Types.IsStruct(t))
    {
        var si = GetStructInfo(cg, t);
        var se = cg.Structs.Get(si.Entry);
        var found = List<Candidate>.Create();
        foreach (var m in se.Methods)
        {
            if (cg.Funcs.Get(m).Decl.Name == name)
                found.Add(Candidate { Entry = m, Owner = t });
        }
        if (found.Count() > 0)
            return found.ToArray();
        t = si.Base;
    }
    return new Candidate[0];
}

// The struct the current function is a method of (0 for free functions).
int CurrentOwner(const ref Compiler cg)
{
    return cg.Instances.Get(cg.Fn[0].Func).Owner;
}

Value ThisValue(const ref Compiler cg, SourceLoc loc)
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

Value FieldAccess(const ref Compiler cg, Value obj, string name, SourceLoc loc)
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
Value EmitStructInit(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetStructInit(e);
    if (n.Type.IsNull())
        Fail(cg, e.Loc, TypelessNewError());
    int t = DeclTypeOf(cg, n.Type);
    if (!types.IsStruct(t))
        Fail(cg, e.Loc, "'" + types.Name(t) + "' is not a struct, initializers are only available for structs");
    return EmitStructInitOf(cg, e, t);
}

// new { ... } / new() as the struct of a target type (see IsTypelessNew).
Value EmitTypelessNew(const ref Compiler cg, Expr e, int target)
{
    int t = TypelessNewType(cg, target);
    if (t == 0)
        Fail(cg, e.Loc, TypelessNewError());
    if (e.Kind == ExprKind.NewObject)
        return Rvalue(t, "zeroinitializer", false);
    return EmitStructInitOf(cg, e, t);
}

// The fields of an initializer in the struct t.
Value EmitStructInitOf(const ref Compiler cg, Expr e, int t)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetStructInit(e);

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
        Value v = ConvertValue(cg, ToRValue(cg, EmitExprAs(cg, f.Value, p.Type)), p.Type, f.Value.Loc);
        agg = ir.InsertValue(ty, agg, LlvmType(cg, p.Type), Consume(cg, v), IndexList(p.Indices));
    }
    return Rvalue(t, agg, NeedsArc(cg, t));
}

// new T(): the zero value of a struct.
Value EmitNewObject(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    var n = cg.Tree.GetNewObject(e);
    if (n.Type.IsNull())
        Fail(cg, e.Loc, TypelessNewError());
    int t = DeclTypeOf(cg, n.Type);
    if (!types.IsStruct(t))
        Fail(cg, e.Loc, "'new' can only create structs and arrays, not '" + types.Name(t) + "'");
    return Rvalue(t, "zeroinitializer", false);
}

// C#'s "Color Color" rule: a local variable or field may have the name of its own type (Color Color). Then 'Color.X'
// means the type when X is not a member of the value: enum members, static methods and constants of the type.
bool ColorColorMeansType(const ref Compiler cg, string name, string member, SourceLoc loc)
{
    var entry = TypeDeclEntry { };
    if (name.Contains('.') || !LookupTypeDecl(cg, cg.Fn[0].File, name, ref entry))
        return false;
    int valueType = 0;
    int local = FindLocal(cg, name);
    if (local >= 0)
        valueType = cg.Fn[0].Vars.Get(local).Type;
    else if (CurrentOwner(cg) != 0 && FindField(cg, CurrentOwner(cg), name).Found)
        valueType = FindField(cg, CurrentOwner(cg), name).Type;
    else
        return false;
    if (entry.Kind == DeclKind.Enum)
        return GetEnumType(cg, entry.Index) == valueType;
    if (entry.Kind != DeclKind.Struct || cg.Structs.Get(entry.Index).Decl.TypeParams.Length > 0 ||
        GetStructType(cg, entry.Index, new int[0], loc) != valueType)
        return false;
    if (FindField(cg, valueType, member).Found)
        return false;
    foreach (var c in MethodCandidates(cg, valueType, member))
    {
        if (!cg.Funcs.Get(c.Entry).Decl.IsStatic)
            return false;
    }
    return true;
}

// obj.Name, Type.Name
Value EmitMember(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    var m = cg.Tree.GetMember(e);

    // Enum<T>.Count, .Min, .Max, .Values, .Names: constants
    int metaEnum = EnumMetaType(cg, m.Object, cg.Fn[0].File, cg.Fn[0].Env);
    if (metaEnum != 0)
        return ConstToValue(cg, EnumMeta(cg, metaEnum, m.Name, e.Loc));

    // A name that is not a variable may be a type or a namespace.
    string dotted = DottedName(cg, m.Object);
    bool colorColor = dotted.Length > 0 && ColorColorMeansType(cg, dotted, m.Name, e.Loc);
    if (dotted.Length > 0 && (!IsLocalName(cg, dotted.Split('.')[0].ToString()) || colorColor))
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
        if (colorColor || CurrentOwner(cg) == 0 || FindField(cg, CurrentOwner(cg), dotted.Split('.')[0].ToString()).Found == false)
        {
            bool isTypeName = LookupTypeDecl(cg, cg.Fn[0].File, dotted, ref entry);
            if (isTypeName && dotted == "Thread" && m.Name == "Cancelled" && entry.Kind == DeclKind.Struct)
                return EmitThreadCancelled(cg, e.Loc);
            if (isTypeName && entry.Kind == DeclKind.Enum)
            {
                int et = GetEnumType(cg, entry.Index);
                var einfo = GetEnumInfo(cg, et);
                int member = FindEnumMember(einfo, m.Name);
                if (member < 0)
                    Fail(cg, e.Loc, "enum '" + types.Name(et) + "' has no member '" + m.Name + "'");
                return ConstInt(cg, et, einfo.Values[member]);
            }
            if (isTypeName || IsNamespace(cg, cg.Fn[0].File, dotted))
            {
                int c = LookupConst(cg, cg.Fn[0].File, dotted + "." + m.Name);
                if (c >= 0)
                    return EmitConst(cg, c, e.Loc);
                int g = LookupGlobal(cg, cg.Fn[0].File, dotted + "." + m.Name);
                if (g >= 0)
                    return GlobalUse(cg, g);
                if (isTypeName && entry.Kind == DeclKind.Struct)
                {
                    // Type.Method as a value: a static method that converts to an Action/Func
                    int owner = GetStructType(cg, entry.Index, ResolveTypeArgs(cg, LastTypeArgs(cg, m.Object)), e.Loc);
                    var methods = MethodCandidates(cg, owner, m.Name);
                    if (methods.Length > 0)
                        return GroupValue(cg, methods, ResolveTypeArgs(cg, m.TypeArgs), types.Name(owner) + "." + m.Name);
                    Fail(cg, e.Loc, "struct '" + types.Name(owner) + "' has no static member '" + m.Name + "'");
                }
                var functions = FreeCandidates(cg, cg.Fn[0].File, dotted + "." + m.Name);
                if (functions.Length > 0)
                    return GroupValue(cg, functions, ResolveTypeArgs(cg, m.TypeArgs), dotted + "." + m.Name);
                Fail(cg, e.Loc, "'" + dotted + "' has no value member '" + m.Name + "'");
            }
        }
    }

    if (!m.ViaArrow)
    {
        Value inPlace = ElementField(cg, e);
        if (!inPlace.IsNone())
            return inPlace;
    }
    Value obj = SettleCollection(cg, EmitExpr(cg, m.Object)); // [1, 2].Length: an array
    if (m.ViaArrow)
        obj = DerefPointer(cg, obj, e.Loc);
    else if (types.IsPointer(obj.Type))
        Fail(cg, e.Loc, "use '->' to access members through a pointer");
    int t = obj.Type;
    if (types.IsStruct(t))
        return FieldAccess(cg, obj, m.Name, e.Loc);
    if ((types.IsString(t) || types.IsArray(t)) && m.Name == "Length")
    {
        Value o = ToRValue(cg, obj);
        HoldTemp(cg, o);
        string len = cg.Ir.Call(SizeIr(cg), "@__cs_len", "ptr " + o.V);
        return Rvalue(types.I32, SizeToI32(cg, len), false);
    }
    if (types.IsFixed(t) && m.Name == "Length")
        return ConstInt(cg, types.I32, (int64)types.Count(t)); // a constant: the number of elements is part of the type
    if (types.IsSlice(t) && m.Name == "Length")
    {
        Value o = ToRValue(cg, obj);
        HoldTemp(cg, o);
        string len = cg.Ir.ExtractValue(LlvmType(cg, t), o.V, "2");
        return Rvalue(types.I32, SizeToI32(cg, len), false);
    }
    if (types.IsError(t) && (m.Name == "Message" || m.Name == "Code"))
    {
        Value o = ToRValue(cg, obj);
        HoldTemp(cg, o);
        if (m.Name == "Message")
            return Rvalue(types.String, cg.Ir.ExtractValue(LlvmType(cg, t), o.V, "2"), false);
        // Error<T, E>: the code is a value of the error enum E
        int codeType = types.Code(t) != 0 ? types.Code(t) : types.I32;
        return Rvalue(codeType, cg.Ir.ExtractValue(LlvmType(cg, t), o.V, "3"), false);
    }
    Fail(cg, e.Loc, "type '" + types.Name(t) + "' has no member '" + m.Name + "'");
    return obj;
}

// ---------------------------------------------------------------------------
// Reference counting of structs: one helper function per type
// ---------------------------------------------------------------------------

// Name of the retain/release helper of a struct type; the helper is written the first time it is needed.
string StructHelper(const ref Compiler cg, int t, bool isRetain)
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
string MemberHelperCall(const ref Compiler cg, int memberType, int index, int n, bool isRetain, string structIr)
{
    string reg = "%m" + n.ToString();
    string callee = isRetain ? RetainFunction(cg, memberType) : ReleaseFunction(cg, memberType);
    string call = "call void " + callee + "(" + LlvmType(cg, memberType) + " " + reg + ")";
    return "  " + reg + " = extractvalue " + structIr + " %v, " + index.ToString() + "\n  " + call + "\n";
}

// int.MaxValue, float.Epsilon, ...: constants of the built-in number types. Returns false if there is no such member.
bool EmitBuiltinStaticMember(const ref Compiler cg, int type, string member, ref Value result)
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

// ---------------------------------------------------------------------------
// Fields of list elements
// ---------------------------------------------------------------------------

// list.Get(i).A.B (also list[i].A.B) on a List of structs: the field is read where the element is (List._At) and only
// its value is copied - not the whole element with all its references, as Get would. Only where everything is known
// before any code is written: the list is a variable, a parameter or a field (PathType) and every name is a field;
// otherwise Value { } and the expression is compiled as usual.
Value ElementField(const ref Compiler cg, Expr e)
{
    var tree = cg.Tree;
    var types = cg.Types;
    var names = List<string>.Create();
    Expr cur = e;
    while (cur.Kind == ExprKind.Member && !tree.GetMember(cur).ViaArrow)
    {
        names.Insert(0, tree.GetMember(cur).Name);
        cur = tree.GetMember(cur).Object;
    }
    Expr list = Expr { };
    Expr index = Expr { };
    if (cur.Kind == ExprKind.Call)
    {
        var c = tree.GetCall(cur);
        if (c.Callee.Kind != ExprKind.Member || c.Args.Length != 1)
            return Value { };
        var callee = tree.GetMember(c.Callee);
        if (callee.Name != "Get" || callee.ViaArrow || callee.TypeArgs.Length > 0)
            return Value { };
        list = callee.Object;
        index = c.Args[0];
    }
    else if (cur.Kind == ExprKind.Index && !tree.GetIndex(cur).FromEnd)
    {
        list = tree.GetIndex(cur).Object;
        index = tree.GetIndex(cur).Index;
    }
    else
        return Value { };
    if (index.Kind == ExprKind.RefArg)
        return Value { };
    int lt = PathType(cg, list);
    if (lt <= 0 || !types.IsStruct(lt))
        return Value { };
    var si = GetStructInfo(cg, lt);
    var decl = cg.Structs.Get(si.Entry).Decl;
    if (decl.Name != "List" || decl.TypeParams.Length != 1 || !cg.Files.Get(cg.Structs.Get(si.Entry).File).IsPrelude)
        return Value { };
    var at = MethodCandidates(cg, lt, "_At");
    if (at.Length != 1 || MethodCandidates(cg, lt, "Get").Length != 1)
        return Value { };
    int elem = 0;
    if (si.Env.TryGet(decl.TypeParams[0]) is int found)
        elem = found;
    if (elem <= 0 || !types.IsStruct(elem))
        return Value { };
    // the fields, from the element outwards
    int t = elem;
    var paths = List<int[]>.Create();
    foreach (var name in names)
    {
        if (!types.IsStruct(t))
            return Value { };
        var p = FindField(cg, t, name);
        if (!p.Found || (p.IsPrivate && CurrentOwner(cg) != p.Owner))
            return Value { };
        paths.Add(p.Indices);
        t = p.Type;
    }

    var ir = cg.Ir;
    Value lv = EmitExpr(cg, list);
    var args = new Arg[1];
    args[0] = Arg { V = EmitRValue(cg, index), Source = index };
    int instance = ResolveOverload(cg, at, args, new int[0], e.Loc, "_At");
    string addr = CallMethodOn(cg, lv, instance, "_At", args, e.Loc).V;
    int ft = elem;
    for (var i = 0; i < paths.Count(); i += 1)
    {
        var sb = StringBuilder.Create();
        sb.Append("i32 0");
        foreach (var k in paths.Get(i))
            sb.Append(", i32 " + k.ToString());
        addr = ir.Gep(LlvmType(cg, ft), addr, sb.ToString());
        ft = FindField(cg, ft, names.Get(i)).Type;
    }
    string value = ir.Load(LlvmType(cg, ft), addr);
    EmitRetain(cg, ft, value); // its own reference: the list may change before the value is used
    return Rvalue(ft, value, NeedsArc(cg, ft));
}

// The type of a variable, a parameter, a field of 'this' or a field of one of them, without writing code; 0 for any
// other expression.
int PathType(const ref Compiler cg, Expr e)
{
    var tree = cg.Tree;
    if (e.Kind == ExprKind.Name)
    {
        string name = tree.GetName(e).Name;
        int local = FindLocal(cg, name);
        if (local >= 0)
        {
            var v = cg.Fn[0].Vars.Get(local);
            return v.IsConstant || v.Slot.Length == 0 ? 0 : v.Type;
        }
        if (cg.Fn[0].LambdaId > 0)
            return 0; // perhaps a variable of an enclosing function
        int owner = CurrentOwner(cg);
        if (owner == 0)
            return 0;
        var p = FindField(cg, owner, name);
        return p.Found ? p.Type : 0;
    }
    if (e.Kind == ExprKind.Member)
    {
        var m = tree.GetMember(e);
        if (m.ViaArrow)
            return 0;
        int t = PathType(cg, m.Object);
        if (t <= 0 || !cg.Types.IsStruct(t))
            return 0;
        var p = FindField(cg, t, m.Name);
        return p.Found ? p.Type : 0;
    }
    return 0;
}
