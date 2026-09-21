// The state of the compiler: declarations, types, function instances and the function being generated.
//
// This is a port of the class CodeGen (compiler/src/CodeGen.h/.cpp). CShift structs cannot be split over several
// files, so the C++ member functions become free functions that take the Compiler; they live in Compiler.csh
// (declarations, types, function instances), Convert.csh (conversions), Expr.csh, Call.csh, Stmt.csh and Module.csh.
// The Compiler is a handle: all mutable state is in lists, dictionaries and small arrays, so copies share it.
//
// Errors: the first error is printed and ends the compiler (Fail).

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// ---------------------------------------------------------------------------
// Registered declarations. A declaration is referred to by its index in the compiler's list.
// ---------------------------------------------------------------------------

enum DeclKind : int32 { Struct, Interface, Enum }

struct TypeDeclEntry
{
    DeclKind Kind;
    int Index; // index in Compiler.Structs / Interfaces / Enums
}

struct FuncEntry
{
    FuncDecl Decl;
    int File;        // index in Compiler.Files
    int OwnerStruct; // index in Compiler.Structs for methods, otherwise -1
}

struct StructEntry
{
    StructDecl Decl;
    int File;
    int[] Methods;   // indices in Compiler.Funcs
}

struct InterfaceEntry
{
    InterfaceDecl Decl;
    int File;
    int[] Methods;
}

struct EnumEntry
{
    EnumDecl Decl;
    int File;
}

struct ConstEntry
{
    ConstDecl Decl;
    int File;
}

// ---------------------------------------------------------------------------
// Function instances: a function with its type arguments filled in (monomorphization)
// ---------------------------------------------------------------------------

struct FuncInfo
{
    int Entry;                        // index in Compiler.Funcs
    int File;
    int Owner;                        // struct type for methods, otherwise 0
    Dictionary<string, int> Env;      // type parameters (of the owner and of the function)
    string Name;                      // display name
    int[] ParamTypes;
    int[] ParamRefs;                  // RefKind as int
    int Ret;
    bool HasThis;
    string LlvmName;
    bool Queued;
    bool SignatureResolved;
}

// ---------------------------------------------------------------------------
// The value of an expression
// ---------------------------------------------------------------------------

struct Value
{
    int Type;
    string V;          // the operand (a register, a constant, or the address for an lvalue)
    bool IsLValue;
    bool IsConst;      // an lvalue that must not be written
    bool Owned;        // an rvalue that carries a +1 reference count (ARC types only)
    bool IsRefArg;     // was written as 'ref x'
    bool HasLit;       // an integer or float literal that adapts to the type it is used with
    bool LitIsFloat;
    int64 LitInt;
    double LitFloat;

    bool IsNone()
    {
        return Type == 0;
    }
}

Value Rvalue(int type, string v, bool owned)
{
    return Value { Type = type, V = v, Owned = owned };
}

Value Lvalue(int type, string addr, bool isConst)
{
    return Value { Type = type, V = addr, IsLValue = true, IsConst = isConst };
}

// ---------------------------------------------------------------------------
// The function being generated
// ---------------------------------------------------------------------------

struct ScopeVar
{
    string Name;
    int Type;
    string Slot;
    bool IsRef;        // the slot holds a pointer to the real storage (ref parameters)
    bool IsConst;
    bool OwnsArc;      // release at the end of the scope
    bool Disposable;   // call Dispose() at the end of the scope
    bool ResetOnCleanup; // zero the slot after releasing (pattern variables)
}

struct TempRelease
{
    int Type;
    string Value;
}

struct LoopCtx
{
    string BreakLabel;
    string ContinueLabel; // empty for switch
    int ScopeDepth;
}

struct FnState
{
    int Func;             // index in Compiler.Instances
    int RetType;
    string RetLlvm;
    List<ScopeVar> Vars;
    List<int> ScopeStarts;   // start of every scope in Vars
    List<TempRelease> Temps;
    List<LoopCtx> Loops;
    int UnsafeDepth;
    bool Checked;
    string ThisSlot;
    bool IsIntMain;
    int File;                          // file context of the function (for name lookup)
    Dictionary<string, int> Env;       // its type parameters
}

struct CgState
{
    int MainFunc;         // index in Compiler.Instances + 1, 0 = none
    int WorkHead;         // next entry of the work queue
    bool Windows;
    bool ArcStats;        // count heap blocks and print the balance at the end (--arc-stats)
    bool StdlibLoaded;    // the standard library was added as prelude
}

// ---------------------------------------------------------------------------
// The compiler
// ---------------------------------------------------------------------------

struct Compiler
{
    Ast Tree;
    Diagnostics Diag;
    TypeContext Types;
    IrWriter Ir;
    CgState[] St;
    FnState[] Fn;

    List<FileContext> Files;
    List<FuncEntry> Funcs;
    List<StructEntry> Structs;
    List<InterfaceEntry> Interfaces;
    List<EnumEntry> Enums;
    List<EnumInfo> EnumInfos;
    List<InterfaceInfo> InterfaceInfos;
    Dictionary<string, int> InterfaceTypes;
    List<int> PendingVerify;   // struct types whose interfaces still have to be checked
    Dictionary<string, int> EnumTypes;
    List<ConstEntry> Consts;
    Dictionary<string, TypeDeclEntry> TypeDecls;
    Dictionary<string, List<int>> FuncDecls;
    Dictionary<string, int> ConstDecls;
    HashSet<string> Namespaces;
    HashSet<string> Symbols;     // names of the generated functions (to find duplicates)
    List<string> Links;

    List<StructInfo> StructInfos;
    Dictionary<string, int> StructTypes;
    List<FuncInfo> Instances;
    Dictionary<string, int> InstanceKeys;
    List<int> WorkQueue;

    static Compiler Create(Ast tree, Diagnostics diag, bool windows)
    {
        var cg = Compiler { Tree = tree, Diag = diag };
        cg.Types = TypeContext.Create();
        cg.Ir = IrWriter.Create();
        cg.St = new CgState[1];
        cg.St[0].Windows = windows;
        cg.Fn = new FnState[1];
        cg.Files = List<FileContext>.Create();
        cg.Funcs = List<FuncEntry>.Create();
        cg.Structs = List<StructEntry>.Create();
        cg.Interfaces = List<InterfaceEntry>.Create();
        cg.Enums = List<EnumEntry>.Create();
        cg.EnumInfos = List<EnumInfo>.Create();
        cg.InterfaceInfos = List<InterfaceInfo>.Create();
        cg.InterfaceTypes = Dictionary<string, int>.Create();
        cg.PendingVerify = List<int>.Create();
        cg.EnumTypes = Dictionary<string, int>.Create();
        cg.Consts = List<ConstEntry>.Create();
        cg.TypeDecls = Dictionary<string, TypeDeclEntry>.Create();
        cg.FuncDecls = Dictionary<string, List<int>>.Create();
        cg.ConstDecls = Dictionary<string, int>.Create();
        cg.Namespaces = HashSet<string>.Create();
        cg.Symbols = HashSet<string>.Create();
        cg.Namespaces.Add("System");
        cg.Links = List<string>.Create();
        cg.StructInfos = List<StructInfo>.Create();
        cg.StructTypes = Dictionary<string, int>.Create();
        cg.Instances = List<FuncInfo>.Create();
        cg.InstanceKeys = Dictionary<string, int>.Create();
        cg.WorkQueue = List<int>.Create();
        return cg;
    }
}

// Reports an error and ends the compiler.
void Fail(Compiler cg, SourceLoc loc, string message)
{
    cg.Diag.ReportAt(loc, message);
    Environment.Exit(1);
}

// ---------------------------------------------------------------------------
// Registration and lookup of declarations
// ---------------------------------------------------------------------------

string Qualified(Compiler cg, int file, string name)
{
    string ns = cg.Files.Get(file).Ns;
    return ns.Length == 0 ? name : ns + "." + name;
}

void AddUnit(Compiler cg, CompilationUnit unit)
{
    cg.Files.Add(unit.File);
    int file = cg.Files.Count() - 1;

    if (unit.File.Ns.Length > 0)
    {
        // every prefix of a namespace is a namespace: A.B.C also makes A and A.B
        string prefix = "";
        foreach (var part in unit.File.Ns.Split('.'))
        {
            prefix += (prefix.Length > 0 ? "." : "") + part;
            cg.Namespaces.Add(prefix);
        }
    }

    for (var i = 0; i < unit.Structs.Count(); i += 1)
    {
        var s = unit.Structs.Get(i);
        var methods = List<int>.Create();
        for (var k = 0; k < s.Methods.Length; k += 1)
        {
            methods.Add(cg.Funcs.Count());
            cg.Funcs.Add(FuncEntry { Decl = s.Methods[k], File = file, OwnerStruct = cg.Structs.Count() });
        }
        cg.Structs.Add(StructEntry { Decl = s, File = file, Methods = methods.ToArray() });
        AddTypeDecl(cg, file, s.Name, s.Loc, TypeDeclEntry { Kind = DeclKind.Struct, Index = cg.Structs.Count() - 1 });
    }
    for (var i = 0; i < unit.Interfaces.Count(); i += 1)
    {
        var d = unit.Interfaces.Get(i);
        var methods = List<int>.Create();
        for (var k = 0; k < d.Methods.Length; k += 1)
        {
            methods.Add(cg.Funcs.Count());
            cg.Funcs.Add(FuncEntry { Decl = d.Methods[k], File = file, OwnerStruct = -2 }); // -2: interface method
        }
        cg.Interfaces.Add(InterfaceEntry { Decl = d, File = file, Methods = methods.ToArray() });
        AddTypeDecl(cg, file, d.Name, d.Loc, TypeDeclEntry { Kind = DeclKind.Interface, Index = cg.Interfaces.Count() - 1 });
    }
    for (var i = 0; i < unit.Enums.Count(); i += 1)
    {
        var d = unit.Enums.Get(i);
        cg.Enums.Add(EnumEntry { Decl = d, File = file });
        AddTypeDecl(cg, file, d.Name, d.Loc, TypeDeclEntry { Kind = DeclKind.Enum, Index = cg.Enums.Count() - 1 });
    }
    for (var i = 0; i < unit.Funcs.Count(); i += 1)
    {
        var f = unit.Funcs.Get(i);
        cg.Funcs.Add(FuncEntry { Decl = f, File = file, OwnerStruct = -1 });
        string q = Qualified(cg, file, f.Name);
        var existing = cg.FuncDecls.TryGet(q);
        if (existing is List<int> list)
        {
            list.Add(cg.Funcs.Count() - 1);
        }
        else
        {
            var fresh = List<int>.Create();
            fresh.Add(cg.Funcs.Count() - 1);
            cg.FuncDecls.Set(q, fresh);
        }
    }
    for (var i = 0; i < unit.Consts.Count(); i += 1)
    {
        var c = unit.Consts.Get(i);
        string q = Qualified(cg, file, c.Name);
        if (cg.ConstDecls.ContainsKey(q))
        {
            Fail(cg, c.Loc, "constant '" + q + "' is already defined");
        }
        cg.Consts.Add(ConstEntry { Decl = c, File = file });
        cg.ConstDecls.Set(q, cg.Consts.Count() - 1);
    }
    for (var i = 0; i < unit.Links.Count(); i += 1)
        cg.Links.Add(unit.Links.Get(i));
}

void AddTypeDecl(Compiler cg, int file, string name, SourceLoc loc, TypeDeclEntry entry)
{
    string q = Qualified(cg, file, name);
    if (cg.TypeDecls.ContainsKey(q))
        Fail(cg, loc, "type '" + q + "' is already defined");
    cg.TypeDecls.Set(q, entry);
}

// The names a simple name can stand for in a file, in lookup order: the file's own namespace (and its parents),
// then the global namespace (they win over 'using' directives, like in C#), then the 'using' namespaces.
string[] CandidateNames(Compiler cg, int file, string name)
{
    var f = cg.Files.Get(file);
    var names = List<string>.Create();
    string ns = f.Ns;
    while (ns.Length > 0)
    {
        names.Add(ns + "." + name);
        int dot = ns.LastIndexOf('.');
        ns = dot < 0 ? "" : ns.Substring(0, dot);
    }
    names.Add(name);
    for (var i = 0; i < f.Usings.Count(); i += 1)
        names.Add(f.Usings.Get(i) + "." + name);
    return names.ToArray();
}

// Finds a struct, interface or enum; returns false if there is none.
bool LookupTypeDecl(Compiler cg, int file, string name, ref TypeDeclEntry entry)
{
    foreach (var c in CandidateNames(cg, file, name))
    {
        var found = cg.TypeDecls.TryGet(c);
        if (found is TypeDeclEntry e)
        {
            entry = e;
            return true;
        }
    }
    return false;
}

// All functions a name can refer to (indices in Compiler.Funcs).
int[] LookupFunctions(Compiler cg, int file, string name)
{
    var result = List<int>.Create();
    foreach (var c in CandidateNames(cg, file, name))
    {
        var found = cg.FuncDecls.TryGet(c);
        if (found is List<int> list)
        {
            for (var i = 0; i < list.Count(); i += 1)
            {
                int f = list.Get(i);
                if (!result.Contains(f))
                    result.Add(f);
            }
        }
    }
    return result.ToArray();
}

bool IsNamespace(Compiler cg, int file, string name)
{
    foreach (var c in CandidateNames(cg, file, name))
        if (cg.Namespaces.Contains(c))
            return true;
    return false;
}

int LookupConst(Compiler cg, int file, string name)
{
    foreach (var c in CandidateNames(cg, file, name))
    {
        var found = cg.ConstDecls.TryGet(c);
        if (found is int index)
            return index;
    }
    return -1;
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

// The type for a primitive type name, or 0.
int PrimitiveType(Compiler cg, string name)
{
    var t = cg.Types;
    switch (name)
    {
    case "int": return t.I32;
    case "int32": return t.I32;
    case "uint": return t.U32;
    case "uint32": return t.U32;
    case "float": return t.F32;
    case "float32": return t.F32;
    case "double": return t.F64;
    case "float64": return t.F64;
    case "int8": return t.I8;
    case "int16": return t.I16;
    case "int64": return t.I64;
    case "uint8": return t.U8;
    case "uint16": return t.U16;
    case "uint64": return t.U64;
    case "bool": return t.Bool;
    case "char": return t.Char;
    case "string": return t.String;
    case "void": return t.Void;
    case "nint": return t.Nint;
    case "nuint": return t.Nuint;
    default: return 0;
    }
}

int ResolveValueType(Compiler cg, int refType, int file, Dictionary<string, int> env)
{
    int t = ResolveType(cg, refType, file, env);
    var node = cg.Tree.GetType(TypeRef { Id = refType });
    if (cg.Types.Kind(t) == TypeKind.Interface)
        Fail(cg, node.Loc, "interface '" + cg.Types.Name(t) + "' can only be used as a generic constraint or in a base list");
    return t;
}

// Resolves a type as written in the source. 'refType' is a TypeRef id. 'env' maps type parameters to types (may be null).
int ResolveType(Compiler cg, int refType, int file, Dictionary<string, int> env)
{
    var tree = cg.Tree;
    var node = tree.GetType(TypeRef { Id = refType });
    var types = cg.Types;

    if (node.Kind == TypeRefKind.Pointer)
        return types.PointerTo(ResolveType(cg, node.Elem.Id, file, env));
    if (node.Kind == TypeRefKind.Array)
    {
        int elem = ResolveValueType(cg, node.Elem.Id, file, env);
        if (types.IsVoid(elem))
            Fail(cg, node.Loc, "arrays of 'void' are not allowed");
        return types.ArrayOf(elem);
    }

    string dotted = "";
    for (var i = 0; i < node.Path.Length; i += 1)
        dotted += (i > 0 ? "." : "") + node.Path[i];

    if (node.Path.Length == 1)
    {
        var bound = env.TryGet(dotted);
        if (bound is int b)
            return b;
        int p = PrimitiveType(cg, dotted);
        if (p != 0)
        {
            if (node.Args.Length > 0)
                Fail(cg, node.Loc, "type '" + dotted + "' is not generic");
            return p;
        }
    }

    var entry = TypeDeclEntry { };
    bool found = LookupTypeDecl(cg, file, dotted, ref entry);
    if (!found && node.Path.Length == 1 && (dotted == "Error" || dotted == "Optional"))
    {
        if (node.Args.Length != 1)
            Fail(cg, node.Loc, "'" + dotted + "' expects exactly one type argument");
        int inner = ResolveValueType(cg, node.Args[0].Id, file, env);
        if (types.IsResultLike(inner))
            Fail(cg, node.Loc, "Error<T> and Optional<T> cannot be nested (" + dotted + "<" + types.Name(inner) + ">)");
        // Error<void> is a result without a payload (success or error); Optional<void> makes no sense.
        if (types.IsVoid(inner) && dotted != "Error")
            Fail(cg, node.Loc, dotted + "<void> is not supported");
        return dotted == "Error" ? types.ErrorOf(inner) : types.OptionalOf(inner);
    }
    if (!found && node.Path.Length == 1 && (dotted == "Action" || dotted == "Func"))
        return ResolveFunctionType(cg, node, dotted, file, env);
    if (!found && node.Path.Length == 1 && !cg.St[0].StdlibLoaded && IsStdlibName(dotted))
        Fail(cg, node.Loc, "cshc does not support the standard library yet ('" + dotted + "')");
    if (!found)
        Fail(cg, node.Loc, "unknown type '" + tree.TypeToString(TypeRef { Id = refType }) + "'");

    var typeArgs = new int[node.Args.Length];
    for (var i = 0; i < node.Args.Length; i += 1)
        typeArgs[i] = ResolveValueType(cg, node.Args[i].Id, file, env);
    if (entry.Kind == DeclKind.Struct)
        return GetStructType(cg, entry.Index, typeArgs, node.Loc);
    if (entry.Kind == DeclKind.Enum)
    {
        if (typeArgs.Length > 0)
            Fail(cg, node.Loc, "enum '" + dotted + "' is not generic");
        return GetEnumType(cg, entry.Index);
    }
    return GetInterfaceType(cg, entry.Index, typeArgs, node.Loc);
}

// Action, Action<T1, ...> (no result) and Func<R>, Func<T1, ..., R> (the last argument is the result): pointers to
// functions, like delegates in C# but without closures.
int ResolveFunctionType(Compiler cg, TypeRefNode node, string dotted, int file, Dictionary<string, int> env)
{
    var types = cg.Types;
    Fail(cg, node.Loc, "cshc does not support function pointers (Action/Func) yet");
    bool isAction = dotted == "Action";
    if (!isAction && node.Args.Length == 0)
        Fail(cg, node.Loc, "'Func' needs at least the result type: Func<TResult>, Func<TArg, TResult>, ...");
    var parameters = List<int>.Create();
    int ret = types.Void;
    for (var i = 0; i < node.Args.Length; i += 1)
    {
        int t = ResolveValueType(cg, node.Args[i].Id, file, env);
        if (!isAction && i + 1 == node.Args.Length)
        {
            if (types.IsVoid(t))
                Fail(cg, node.Loc, "use 'Action' for functions without a result, not Func<..., void>");
            ret = t;
            break;
        }
        if (types.IsVoid(t))
            Fail(cg, node.Loc, "a function parameter cannot have type 'void'");
        parameters.Add(t);
    }
    if (parameters.Count() > 8)
        Fail(cg, node.Loc, "'" + dotted + "' supports at most 8 parameters");
    return types.FunctionOf(parameters.ToArray(), ret);
}

// The LLVM type of a type, as text.
string LlvmType(Compiler cg, int t)
{
    var types = cg.Types;
    switch (types.Kind(t))
    {
    case TypeKind.Void: return "void";
    case TypeKind.Bool: return "i1";
    case TypeKind.Int:
    case TypeKind.Char:
    case TypeKind.Enum:
        return "i" + types.Bits(t).ToString();
    case TypeKind.Float:
        return types.Bits(t) == 32 ? "float" : "double";
    case TypeKind.Error:
    {
        int elem = types.Elem(t);
        // Error<void> keeps the same layout with an empty payload so that member indices stay the same.
        string payload = types.IsVoid(elem) ? "{}" : LlvmType(cg, elem);
        return "{ i1, " + payload + ", ptr, i32 }";
    }
    case TypeKind.Optional:
        return "{ i1, " + LlvmType(cg, types.Elem(t)) + " }";
    case TypeKind.ErrorLit:
        return "{ ptr, i32 }";
    case TypeKind.Struct:
        return StructIrName(cg, t);
    default:
        return "ptr"; // string, pointer, array, null, function
    }
}

// True if values of the type own a reference count that must be released.
bool NeedsArc(Compiler cg, int t)
{
    var types = cg.Types;
    var info = types.Info(t);
    if (info.Arc >= 0)
        return info.Arc != 0;
    bool r = false;
    switch (info.Kind)
    {
    case TypeKind.String:
    case TypeKind.Array:
    case TypeKind.Error:
    case TypeKind.ErrorLit:
        r = true;
        break;
    case TypeKind.Optional:
        r = NeedsArc(cg, info.Elem);
        break;
    case TypeKind.Struct:
        r = StructNeedsArc(cg, t);
        break;
    default:
        break;
    }
    info = types.Info(t);
    info.Arc = r ? 1 : 0;
    types.SetInfo(t, info);
    return r;
}

// ---------------------------------------------------------------------------
// Function instances
// ---------------------------------------------------------------------------

// Finds or creates the instance of a function for the given type arguments.
int GetFuncInstance(Compiler cg, int entry, int owner, Dictionary<string, int> ownerEnv, int[] typeArgs, SourceLoc loc)
{
    var fe = cg.Funcs.Get(entry);
    var d = fe.Decl;
    if (typeArgs.Length != d.TypeParams.Length)
        Fail(cg, loc, "function '" + d.Name + "' expects " + d.TypeParams.Length.ToString() + " type argument(s), got " +
                          typeArgs.Length.ToString());

    string key = entry.ToString() + "|" + owner.ToString();
    foreach (var a in typeArgs)
        key += "|" + cg.Types.Name(a);
    var existing = cg.InstanceKeys.TryGet(key);
    if (existing is int found)
        return found;

    var fi = FuncInfo { Entry = entry, File = fe.File, Owner = owner };
    fi.Env = Dictionary<string, int>.Create();
    foreach (var kv in ownerEnv.Entries())
        fi.Env.Set(kv.Key, kv.Value);
    for (var i = 0; i < typeArgs.Length; i += 1)
        fi.Env.Set(d.TypeParams[i], typeArgs[i]);
    fi.Name = owner != 0 ? cg.Types.Name(owner) + "." + d.Name : Qualified(cg, fe.File, d.Name);
    if (typeArgs.Length > 0)
    {
        fi.Name += "<";
        for (var i = 0; i < typeArgs.Length; i += 1)
            fi.Name += (i > 0 ? "," : "") + cg.Types.Name(typeArgs[i]);
        fi.Name += ">";
    }
    fi.HasThis = owner != 0 && !d.IsStatic;
    cg.Instances.Add(fi);
    int index = cg.Instances.Count() - 1;
    cg.InstanceKeys.Set(key, index);
    CheckConstraints(cg, d.Constraints, fi.Env, fe.File, loc);
    EnsureSignature(cg, index);
    return index;
}

void EnsureSignature(Compiler cg, int instance)
{
    var fi = cg.Instances.Get(instance);
    if (fi.SignatureResolved)
        return;
    var d = cg.Funcs.Get(fi.Entry).Decl;
    var paramTypes = new int[d.Params.Length];
    var paramRefs = new int[d.Params.Length];
    for (var i = 0; i < d.Params.Length; i += 1)
    {
        var p = d.Params[i];
        int t = ResolveValueType(cg, p.Type.Id, fi.File, fi.Env);
        if (cg.Types.IsVoid(t))
            Fail(cg, p.Loc, "parameter '" + p.Name + "' cannot have type 'void'");
        paramTypes[i] = t;
        paramRefs[i] = (int)p.Ref;
    }
    fi.ParamTypes = paramTypes;
    fi.ParamRefs = paramRefs;
    fi.Ret = ResolveValueType(cg, d.Ret.Id, fi.File, fi.Env);
    if (d.IsExtern)
    {
        // Aggregates are not passed according to the C ABI yet, so only scalars and pointers are allowed.
        for (var i = 0; i < paramTypes.Length; i += 1)
        {
            int t = paramTypes[i];
            if (paramRefs[i] == 0 && (cg.Types.IsStruct(t) || cg.Types.IsResultLike(t)))
                Fail(cg, d.Loc, "extern function '" + d.Name + "': passing '" + cg.Types.Name(t) + "' by value to C is not supported, pass a pointer instead");
        }
        if (!d.RetOut && (cg.Types.IsStruct(fi.Ret) || cg.Types.IsResultLike(fi.Ret)))
            Fail(cg, d.Loc, "extern function '" + d.Name + "': returning '" + cg.Types.Name(fi.Ret) + "' by value from C is not supported, use a pointer instead");
    }
    fi.SignatureResolved = true;
    fi.LlvmName = FunctionSymbol(cg, fi);
    if (!d.IsExtern && !cg.Symbols.Add(fi.LlvmName))
        Fail(cg, d.Loc, "function '" + fi.LlvmName.Substring(2, fi.LlvmName.Length - 3) + "' is already defined");
    cg.Instances.Set(instance, fi);
}

// The name of the function in the IR: Name(param types), like in the C++ compiler; extern functions keep their C name.
string FunctionSymbol(Compiler cg, FuncInfo fi)
{
    var d = cg.Funcs.Get(fi.Entry).Decl;
    if (d.IsExtern)
        return "@" + (d.Symbol != null && d.Symbol.Length > 0 ? d.Symbol : d.Name);
    string name = fi.Name + "(";
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        string prefix = fi.ParamRefs[i] == 1 ? "ref " : (fi.ParamRefs[i] == 2 ? "const ref " : "");
        name += (i > 0 ? "," : "") + prefix + cg.Types.Name(fi.ParamTypes[i]);
    }
    return "@\"" + name + ")\"";
}

// Makes sure the body of the function will be generated.
void UseFunction(Compiler cg, int instance)
{
    var fi = cg.Instances.Get(instance);
    var d = cg.Funcs.Get(fi.Entry).Decl;
    if (d.IsExtern)
    {
        DeclareExtern(cg, instance);
        return;
    }
    if (d.Body.IsNull())
        Fail(cg, d.Loc, "function '" + fi.Name + "' has no body");
    if (!fi.Queued)
    {
        fi.Queued = true;
        cg.Instances.Set(instance, fi);
        cg.WorkQueue.Add(instance);
    }
}

// "declare <ret> @name(<param types>)" for an extern "C" function.
void DeclareExtern(Compiler cg, int instance)
{
    var fi = cg.Instances.Get(instance);
    var d = cg.Funcs.Get(fi.Entry).Decl;
    var sb = StringBuilder.Create();
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        if (i > 0)
            sb.Append(", ");
        sb.Append(fi.ParamRefs[i] != 0 ? "ptr" : LlvmType(cg, fi.ParamTypes[i]));
    }
    if (d.IsVariadic)
        sb.Append(fi.ParamTypes.Length > 0 ? ", ..." : "...");
    cg.Ir.Declare(fi.LlvmName, "declare " + LlvmType(cg, fi.Ret) + " " + fi.LlvmName + "(" + sb.ToString() + ")");
}

// An empty type environment (a Dictionary is a struct, so 'null' cannot stand for "none").
Dictionary<string, int> NoEnv()
{
    return Dictionary<string, int>.Create();
}

// Names of the standard library (stdlib/*.csh). cshc does not load the library yet, so a use of one of these names
// is reported as "not supported" instead of "unknown".
bool IsStdlibName(string name)
{
    return name == "List" || name == "Dictionary" || name == "HashSet" || name == "StringBuilder" || name == "KeyValuePair" ||
           name == "Encoding" || name == "Process" || name == "File" || name == "Math" || name == "Char" || name == "String" ||
           name == "IEquatable" || name == "IHashable" || name == "IComparable" || name == "IDisposable";
}
