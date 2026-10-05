// Generics and interfaces: type arguments, inference, constraints and the check that a struct implements its
// interfaces (ports of CodeGen::unify, inferTypeArgs, getInterfaceType, satisfiesInterface, checkConstraints and
// verifyStruct).
//
// Generic functions and structs are instantiated ("monomorphized") for every list of type arguments: the body is
// compiled again with the type parameters bound in the environment of the instance.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;
using CShift.Check;

struct InterfaceInfo
{
    int Entry;                        // index in Compiler.Interfaces
    string Name;                      // including type arguments
    int Type;
    Dictionary<string, int> Env;
}

int[] ResolveTypeArgs(Compiler cg, TypeRef[] refs)
{
    var list = new int[refs.Length];
    for (var i = 0; i < refs.Length; i += 1)
        list[i] = ResolveValueType(cg, refs[i].Id, cg.Fn[0].File, cg.Fn[0].Env);
    return list;
}

// The type arguments written after the last name of A.B<T>.
TypeRef[] LastTypeArgs(Compiler cg, Expr e)
{
    if (e.Kind == ExprKind.Name)
        return cg.Tree.GetName(e).TypeArgs;
    if (e.Kind == ExprKind.Member)
        return cg.Tree.GetMember(e).TypeArgs;
    return new TypeRef[0];
}

string TypeArgsSuffix(Compiler cg, int[] args)
{
    if (args.Length == 0)
        return "";
    string s = "<";
    for (var i = 0; i < args.Length; i += 1)
        s += (i > 0 ? "," : "") + cg.Types.Name(args[i]);
    return s + ">";
}

// ---------------------------------------------------------------------------
// Interfaces
// ---------------------------------------------------------------------------

int GetInterfaceType(Compiler cg, int entry, int[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ie = cg.Interfaces.Get(entry);
    var decl = ie.Decl;
    if (args.Length != decl.TypeParams.Length)
        return RecoverType(cg, loc, "interface '" + decl.Name + "' expects " + decl.TypeParams.Length.ToString() + " type argument(s), got " + args.Length.ToString());
    if (HasUnknownType(cg, args))
        return types.Unknown;
    string key = Qualified(cg, ie.File, decl.Name) + TypeArgsSuffix(cg, args);
    var existing = cg.InterfaceTypes.TryGet(key);
    if (existing is int found)
        return found;

    int t = types.Add(TypeKind.Interface, key, 0, false);
    var info = InterfaceInfo { Entry = entry, Name = key, Type = t };
    info.Env = Dictionary<string, int>.Create();
    for (var i = 0; i < args.Length; i += 1)
        info.Env.Set(decl.TypeParams[i], args[i]);
    cg.InterfaceInfos.Add(info);
    var ti = types.Info(t);
    ti.Decl = cg.InterfaceInfos.Count() - 1;
    types.SetInfo(t, ti);
    cg.InterfaceTypes.Set(key, t);
    return t;
}

bool StructImplements(Compiler cg, int structType, int iface)
{
    int t = structType;
    while (t != 0 && cg.Types.IsStruct(t))
    {
        var si = GetStructInfo(cg, t);
        foreach (var i in si.Interfaces)
        {
            if (i == iface)
                return true;
        }
        t = si.Base;
    }
    return false;
}

bool SatisfiesInterface(Compiler cg, int t, int iface)
{
    if (IsUnionType(cg, t))
        return UnionImplements(cg, t, iface); // its methods are dispatched on the tag
    var types = cg.Types;
    var ii = cg.InterfaceInfos.Get(types.Decl(iface));
    var ie = cg.Interfaces.Get(ii.Entry);
    // Built-in types implement the standard interfaces of the prelude. Their methods are provided by the compiler
    // (numbers, bool, char, enums) or by the String namespace of the standard library (strings and string slices).
    if (cg.Files.Get(ie.File).IsPrelude)
    {
        string name = ie.Decl.Name;
        var self = ii.Env.TryGet("T");
        bool selfArg = false;
        if (self is int s)
            selfArg = s == t;
        bool text = types.IsString(t) || types.IsStringSlice(t);
        bool primitive = types.IsNumeric(t) || types.IsBool(t) || text || types.IsEnum(t);
        if (name == "IComparable" && (types.IsNumeric(t) || text))
            return selfArg;
        if (name == "IEquatable" && primitive)
            return selfArg;
        if (name == "IHashable" && primitive)
            return true;
    }
    if (types.IsStruct(t))
        return StructImplements(cg, t, iface);
    return false;
}

void CheckConstraints(Compiler cg, Constraint[] constraints, Dictionary<string, int> env, int file, SourceLoc loc)
{
    var types = cg.Types;
    foreach (var c in constraints)
    {
        var bound = env.TryGet(c.Param);
        int actual = 0;
        if (bound is int found)
            actual = found;
        else
            Fail(cg, loc, "constraint refers to unknown type parameter '" + c.Param + "'");
        if (types.IsUnknown(actual))
            continue; // a generic body that the checker checks once (docs/semantic-pass.md)
        foreach (var b in c.Bounds)
        {
            int iface = ResolveType(cg, b.Id, file, env);
            if (types.Kind(iface) != TypeKind.Interface)
                Fail(cg, cg.Tree.GetType(b).Loc, "a constraint must be an interface, but '" + types.Name(iface) + "' is not");
            if (!SatisfiesInterface(cg, actual, iface))
                Fail(cg, loc, "type '" + types.Name(actual) + "' does not satisfy the constraint '" + c.Param + " : " + types.Name(iface) + "'");
        }
    }
}

// Checks that a struct provides every method of its interfaces.
void VerifyStruct(Compiler cg, int structType)
{
    var types = cg.Types;
    var si = GetStructInfo(cg, structType);
    var se = cg.Structs.Get(si.Entry);
    foreach (var iface in si.Interfaces)
    {
        var ii = cg.InterfaceInfos.Get(types.Decl(iface));
        var ie = cg.Interfaces.Get(ii.Entry);
        foreach (var m in ie.Decl.Methods)
        {
            // Resolve the interface method signature with the interface's own type arguments.
            var ptypes = new int[m.Params.Length];
            var prefs = new int[m.Params.Length];
            for (var i = 0; i < m.Params.Length; i += 1)
            {
                ptypes[i] = ResolveValueType(cg, m.Params[i].Type.Id, ie.File, ii.Env);
                prefs[i] = (int)m.Params[i].Ref;
            }
            int ret = ResolveValueType(cg, m.Ret.Id, ie.File, ii.Env);

            bool found = false;
            foreach (var c in MethodCandidates(cg, structType, m.Name))
            {
                var cd = cg.Funcs.Get(c.Entry).Decl;
                if (cd.TypeParams.Length > 0 || cd.IsStatic)
                    continue;
                int instance = GetFuncInstance(cg, c.Entry, c.Owner, GetStructInfo(cg, c.Owner).Env, new int[0], cd.Loc);
                var fi = cg.Instances.Get(instance);
                if (fi.Ret != ret || fi.ParamTypes.Length != ptypes.Length)
                    continue;
                bool same = true;
                for (var i = 0; i < ptypes.Length; i += 1)
                {
                    if (fi.ParamTypes[i] != ptypes[i] || fi.ParamRefs[i] != prefs[i])
                        same = false;
                }
                if (same)
                {
                    found = true;
                    break;
                }
            }
            if (!found)
            {
                string sig = types.Name(ret) + " " + m.Name + "(";
                for (var i = 0; i < ptypes.Length; i += 1)
                    sig += (i > 0 ? ", " : "") + types.Name(ptypes[i]);
                sig += ")";
                Fail(cg, se.Decl.Loc, "struct '" + si.Name + "' does not implement '" + types.Name(iface) + "." + sig + "'");
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Type inference
// ---------------------------------------------------------------------------

// Matches the type as written in a parameter ('pattern') against the type of an argument and binds the type
// parameters that occur in it. Returns false if they cannot match.
bool Unify(Compiler cg, TypeRef pattern, int actual, string[] tparams, int file, int[] bound)
{
    var types = cg.Types;
    var node = cg.Tree.GetType(pattern);
    if (node.Kind == TypeRefKind.Pointer)
        return types.IsPointer(actual) && Unify(cg, node.Elem, types.Elem(actual), tparams, file, bound);
    if (node.Kind == TypeRefKind.Array)
    {
        if (types.Kind(actual) == TypeKind.Collection)
            return true; // [a, b] takes the parameter's type; T is inferred from other arguments (or given)
        return types.IsArray(actual) && Unify(cg, node.Elem, types.Elem(actual), tparams, file, bound);
    }

    var kind = types.Kind(actual);
    if (node.Path.Length == 1 && node.Args.Length == 0)
    {
        for (var i = 0; i < tparams.Length; i += 1)
        {
            if (tparams[i] == node.Path[0])
            {
                if (kind == TypeKind.Null || kind == TypeKind.ErrorLit || kind == TypeKind.MethodGroup || kind == TypeKind.Collection)
                    return true; // cannot infer from these; another argument may bind it
                if (bound[i] == 0)
                    bound[i] = actual;
                return true;
            }
        }
        return true;
    }

    var entry = TypeDeclEntry { };
    string name = node.Path.Length == 1 ? node.Path[0] : "";
    if (name == "Error" || name == "Optional")
    {
        if (node.Args.Length == 1 && !LookupTypeDecl(cg, file, name, ref entry))
        {
            if ((name == "Error" && types.IsError(actual)) || (name == "Optional" && types.IsOptional(actual)))
                return Unify(cg, node.Args[0], types.Elem(actual), tparams, file, bound);
            return kind == TypeKind.Null || kind == TypeKind.ErrorLit;
        }
    }
    if (name == "Slice" && node.Args.Length == 1 && !LookupTypeDecl(cg, file, name, ref entry))
    {
        // Slice<T> from a slice or an array (which converts to a slice of itself)
        if (kind == TypeKind.Slice || kind == TypeKind.Array)
            return Unify(cg, node.Args[0], types.Elem(actual), tparams, file, bound);
        return kind == TypeKind.Null || kind == TypeKind.Collection;
    }
    if (name == "Fixed" && node.Args.Length == 2 && !LookupTypeDecl(cg, file, name, ref entry))
    {
        // Fixed<T, N>: the element type (the size is checked when the parameter type is resolved)
        if (kind == TypeKind.Fixed)
            return Unify(cg, node.Args[0], types.Elem(actual), tparams, file, bound);
        return kind == TypeKind.Collection;
    }
    if (name == "ReadOnlySlice" && node.Args.Length == 1 && !LookupTypeDecl(cg, file, name, ref entry))
    {
        // ReadOnlySlice<T> from any view of array elements or an array
        if (kind == TypeKind.ReadOnlySlice || kind == TypeKind.Slice || kind == TypeKind.Array)
            return Unify(cg, node.Args[0], types.Elem(actual), tparams, file, bound);
        return kind == TypeKind.Null || kind == TypeKind.Collection;
    }
    if (name == "Action" || name == "Func")
    {
        if (!LookupTypeDecl(cg, file, name, ref entry))
        {
            if (kind != TypeKind.Function)
                return kind == TypeKind.Null || kind == TypeKind.MethodGroup;
            bool isFunc = name == "Func";
            int n = node.Args.Length;
            if (isFunc && n == 0)
                return false;
            int paramCount = isFunc ? n - 1 : n;
            var ptypes = types.Params(actual);
            if (paramCount != ptypes.Length || isFunc == types.IsVoid(types.Elem(actual)))
                return false;
            for (var i = 0; i < paramCount; i += 1)
            {
                if (!Unify(cg, node.Args[i], ptypes[i], tparams, file, bound))
                    return false;
            }
            return !isFunc || Unify(cg, node.Args[n - 1], types.Elem(actual), tparams, file, bound);
        }
    }

    if (node.Args.Length > 0 && types.IsStruct(actual))
    {
        string dotted = "";
        for (var i = 0; i < node.Path.Length; i += 1)
            dotted += (i > 0 ? "." : "") + node.Path[i];
        if (LookupTypeDecl(cg, file, dotted, ref entry) && entry.Kind == DeclKind.Struct)
        {
            var si = GetStructInfo(cg, actual);
            var decl = cg.Structs.Get(entry.Index).Decl;
            if (entry.Index == si.Entry && node.Args.Length == decl.TypeParams.Length)
            {
                for (var k = 0; k < node.Args.Length; k += 1)
                {
                    var argT = si.Env.TryGet(decl.TypeParams[k]);
                    if (argT is int at)
                    {
                        if (!Unify(cg, node.Args[k], at, tparams, file, bound))
                            return false;
                    }
                }
            }
        }
    }
    return true;
}

// The type arguments of a call of a generic function from its arguments; false if some cannot be inferred.
bool InferTypeArgs(Compiler cg, Candidate c, Arg[] args, ref int[] result)
{
    var fe = cg.Funcs.Get(c.Entry);
    var d = fe.Decl;
    var bound = new int[d.TypeParams.Length];
    cg.St[0].LambdaError = "";
    for (var i = 0; i < d.Params.Length && i < args.Length; i += 1)
    {
        int actual = args[i].V.Type;
        if (cg.Types.Kind(actual) == TypeKind.Lambda)
            continue; // a lambda takes its types from the parameter; it does not help to infer them
        if (cg.Types.Kind(actual) == TypeKind.MethodGroup)
        {
            int ft = GroupFunctionType(cg, args[i].V); // the natural type of a function name with a single meaning
            if (ft != 0)
                actual = ft;
        }
        if (!Unify(cg, d.Params[i].Type, actual, d.TypeParams, fe.File, bound))
            return false;
    }
    InferFromLambdas(cg, c, args, bound);
    foreach (var b in bound)
    {
        if (b == 0)
            return false;
    }
    result = bound;
    return true;
}

// A lambda passed as a Func<..., R> gives R once its parameter types are known (from the other arguments or other
// lambdas): the type of its body (LambdaResultType), as in list.Select(x => x.Name). Repeats while a lambda binds a
// type parameter that another lambda needs.
void InferFromLambdas(Compiler cg, Candidate c, Arg[] args, int[] bound)
{
    var types = cg.Types;
    var fe = cg.Funcs.Get(c.Entry);
    var d = fe.Decl;
    var entry = TypeDeclEntry { };
    bool progress = true;
    while (progress)
    {
        progress = false;
        for (var i = 0; i < d.Params.Length && i < args.Length; i += 1)
        {
            if (types.Kind(args[i].V.Type) != TypeKind.Lambda)
                continue;
            var node = cg.Tree.GetType(d.Params[i].Type);
            if (node.Kind != TypeRefKind.Named || node.Path.Length != 1 || node.Path[0] != "Func" || node.Args.Length == 0 ||
                LookupTypeDecl(cg, fe.File, "Func", ref entry))
                continue;
            int n = node.Args.Length;
            if (IsPatternBound(cg, node.Args[n - 1], d.TypeParams, bound))
                continue; // nothing left to learn from this lambda
            // the parameter types of the lambda, with the type parameters bound so far (and those of the owner)
            var env = Dictionary<string, int>.Create();
            if (c.Owner != 0)
            {
                foreach (var kv in GetStructInfo(cg, c.Owner).Env.Entries())
                    env.Set(kv.Key, kv.Value);
            }
            for (var k = 0; k < d.TypeParams.Length; k += 1)
            {
                if (bound[k] != 0)
                    env.Set(d.TypeParams[k], bound[k]);
            }
            var paramTypes = new int[n - 1];
            bool ready = true;
            for (var k = 0; k < n - 1; k += 1)
            {
                if (!IsPatternBound(cg, node.Args[k], d.TypeParams, bound))
                    ready = false;
                else
                    paramTypes[k] = ResolveValueType(cg, node.Args[k].Id, fe.File, env);
            }
            if (!ready)
                continue;
            int r = LambdaResultType(cg, args[i].V.LambdaNode, paramTypes);
            if (r == 0 || types.IsVoid(r))
                continue;
            if (Unify(cg, node.Args[n - 1], r, d.TypeParams, fe.File, bound) && IsPatternBound(cg, node.Args[n - 1], d.TypeParams, bound))
                progress = true;
        }
    }
}

// True if every type parameter that occurs in the type as written is bound.
bool IsPatternBound(Compiler cg, TypeRef pattern, string[] tparams, int[] bound)
{
    var node = cg.Tree.GetType(pattern);
    if (node.Kind == TypeRefKind.Pointer || node.Kind == TypeRefKind.Array)
        return IsPatternBound(cg, node.Elem, tparams, bound);
    if (node.Kind == TypeRefKind.Named && node.Path.Length == 1 && node.Args.Length == 0)
    {
        for (var i = 0; i < tparams.Length; i += 1)
        {
            if (tparams[i] == node.Path[0])
                return bound[i] != 0;
        }
    }
    foreach (var a in node.Args)
    {
        if (!IsPatternBound(cg, a, tparams, bound))
            return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// using / IDisposable
// ---------------------------------------------------------------------------

bool ImplementsDisposable(Compiler cg, int t)
{
    int s = t;
    while (s != 0 && cg.Types.IsStruct(s))
    {
        var si = GetStructInfo(cg, s);
        foreach (var i in si.Interfaces)
        {
            var ii = cg.InterfaceInfos.Get(cg.Types.Decl(i));
            var ie = cg.Interfaces.Get(ii.Entry);
            if (ie.Decl.Name == "IDisposable" && cg.Files.Get(ie.File).IsPrelude)
                return true;
        }
        s = si.Base;
    }
    return false;
}

// Calls Dispose() on the variable at the end of its scope.
void CallDispose(Compiler cg, ScopeVar v)
{
    foreach (var c in MethodCandidates(cg, v.Type, "Dispose"))
    {
        var cd = cg.Funcs.Get(c.Entry).Decl;
        if (cd.Params.Length > 0 || cd.TypeParams.Length > 0 || cd.IsStatic)
            continue;
        int instance = GetFuncInstance(cg, c.Entry, c.Owner, GetStructInfo(cg, c.Owner).Env, new int[0], cd.Loc);
        UseFunction(cg, instance);
        NoteCall(cg, instance);
        cg.Ir.Call("void", cg.Instances.Get(instance).LlvmName, "ptr " + v.Slot);
        return;
    }
    Fail(cg, SourceLoc { }, "internal error: missing Dispose method on '" + cg.Types.Name(v.Type) + "'");
}

// using (var r = ...) { body }
void EmitUsingBlock(Compiler cg, Stmt s)
{
    var n = cg.Tree.GetUsingBlock(s);
    PushScope(cg);
    EmitVarDecl(cg, n.Decl);
    EmitStmt(cg, n.Body);
    PopScope(cg, true);
}
