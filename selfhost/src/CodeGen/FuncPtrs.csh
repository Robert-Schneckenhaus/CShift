// Function pointers: Action<...> and Func<..., R> (ports of CodeGen::groupValue, resolveGroup, groupFunctionType and
// emitIndirectCall). A function value is a plain pointer to a function; there are no closures.
//
// A function name used as a value has the type "function" (a method group). It becomes a function pointer when it is
// converted to an Action/Func type; the signature must match exactly.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// A function name used as a value: the functions it can refer to.
Value GroupValue(Compiler cg, Candidate[] cands, int[] typeArgs, string name)
{
    Value v = Rvalue(cg.Types.MethodGroup, "", false);
    v.Group = cands;
    v.GroupTypeArgs = typeArgs;
    v.GroupName = name;
    return v;
}

string FunctionSignature(Compiler cg, FuncInfo fi)
{
    return cg.Types.Name(cg.Types.FunctionOf(fi.ParamTypes, fi.Ret));
}

// Finds the function that a function name refers to when it is converted to the function type 'to'. Returns the
// instance, or -1 with the reason in 'why'.
int ResolveGroup(Compiler cg, Value g, int to, ref string why)
{
    var types = cg.Types;
    string reason = "no function with this name matches";
    var ptypes = types.Params(to);
    foreach (var c in g.Group)
    {
        var fe = cg.Funcs.Get(c.Entry);
        var d = fe.Decl;
        var targs = g.GroupTypeArgs;
        if (d.TypeParams.Length > 0)
        {
            if (targs.Length == 0)
            {
                // Infer the type arguments from the target type.
                var bound = new int[d.TypeParams.Length];
                bool ok = d.Params.Length == ptypes.Length;
                for (var i = 0; ok && i < d.Params.Length; i += 1)
                    ok = Unify(cg, d.Params[i].Type, ptypes[i], d.TypeParams, fe.File, bound);
                if (ok)
                    ok = Unify(cg, d.Ret, types.Elem(to), d.TypeParams, fe.File, bound);
                foreach (var b in bound)
                    ok = ok && b != 0;
                if (!ok)
                {
                    reason = "cannot infer the type arguments of '" + g.GroupName + "', specify them explicitly";
                    continue;
                }
                targs = bound;
            }
            else if (targs.Length != d.TypeParams.Length)
            {
                reason = "wrong number of type arguments";
                continue;
            }
        }
        else if (targs.Length > 0)
        {
            reason = "'" + g.GroupName + "' is not generic";
            continue;
        }

        var ownerEnv = c.Owner != 0 ? GetStructInfo(cg, c.Owner).Env : NoEnv();
        int instance = GetFuncInstance(cg, c.Entry, c.Owner, ownerEnv, targs, d.Loc);
        var fi = cg.Instances.Get(instance);
        if (fi.HasThis)
        {
            reason = "'" + g.GroupName + "' is an instance method; only static methods and free functions can be function values";
            continue;
        }
        bool plain = !d.IsVariadic && !d.RetOut && !d.RetCString;
        for (var i = 0; i < fi.ParamTypes.Length; i += 1)
            plain = plain && fi.ParamRefs[i] == 0 && !d.Params[i].CString;
        if (!plain)
        {
            reason = "'" + g.GroupName + "' has ref parameters or C conversions (string/struct marshalling) and cannot be used as a function pointer";
            continue;
        }
        bool same = fi.ParamTypes.Length == ptypes.Length && fi.Ret == types.Elem(to);
        for (var i = 0; same && i < ptypes.Length; i += 1)
            same = fi.ParamTypes[i] == ptypes[i];
        if (!same)
        {
            reason = "'" + g.GroupName + "' has the signature " + FunctionSignature(cg, fi);
            continue;
        }
        return instance;
    }
    why = reason;
    return -1;
}

// The function type of a function name that has exactly one meaning (for 'var' and type inference); 0 if there is none.
int GroupFunctionType(Compiler cg, Value g)
{
    if (g.Group.Length != 1)
        return 0;
    var c = g.Group[0];
    var d = cg.Funcs.Get(c.Entry).Decl;
    if (d.TypeParams.Length != g.GroupTypeArgs.Length)
        return 0;
    var ownerEnv = c.Owner != 0 ? GetStructInfo(cg, c.Owner).Env : NoEnv();
    int instance = GetFuncInstance(cg, c.Entry, c.Owner, ownerEnv, g.GroupTypeArgs, d.Loc);
    var fi = cg.Instances.Get(instance);
    if (fi.HasThis || d.IsVariadic || d.RetOut || d.RetCString)
        return 0;
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
        if (fi.ParamRefs[i] != 0 || d.Params[i].CString)
            return 0;
    if (fi.ParamTypes.Length > 8)
        return 0;
    return cg.Types.FunctionOf(fi.ParamTypes, fi.Ret);
}

// The value of a function name converted to a function type: the address of the function.
Value ConvertGroup(Compiler cg, Value v, int to, SourceLoc loc)
{
    var types = cg.Types;
    string why = "";
    int instance = -1;
    if (types.IsFunction(to))
        instance = ResolveGroup(cg, v, to, ref why);
    if (instance < 0)
    {
        if (types.IsFunction(to))
            Fail(cg, loc, "cannot convert function '" + v.GroupName + "' to '" + types.Name(to) + "': " + why);
        Fail(cg, loc, "'" + v.GroupName + "' is a function; call it with '()' or assign it to an Action/Func");
    }
    UseFunction(cg, instance);
    NoteCall(cg, instance); // taking the address of a function counts as a call (it is called through the pointer later)
    return Rvalue(to, cg.Instances.Get(instance).LlvmName, false);
}

// A call through a function pointer.
Value EmitIndirectCall(Compiler cg, Value callee, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value f = ToRValue(cg, callee);
    int ft = f.Type;
    var ptypes = types.Params(ft);
    if (args.Length != ptypes.Length)
        Fail(cg, loc, "a call of '" + types.Name(ft) + "' needs " + ptypes.Length.ToString() + " argument(s), got " + args.Length.ToString());

    var callArgs = StringBuilder.Create();
    for (var i = 0; i < args.Length; i += 1)
    {
        SourceLoc aloc = args[i].Source.IsNull() ? loc : args[i].Source.Loc;
        if (args[i].V.IsRefArg)
            Fail(cg, aloc, "function values (Action/Func) have no 'ref' parameters");
        Value cv = ConvertValue(cg, args[i].V, ptypes[i], aloc);
        HoldTemp(cg, cv);
        if (i > 0)
            callArgs.Append(", ");
        callArgs.Append(AbiParam(cg, ptypes[i]) + " " + cv.V);
    }

    EmitPanicIf(cg, ir.ICmp("eq", "ptr", f.V, "null"), "call of a null function");
    int ret = types.Elem(ft);
    string result = ir.Call(AbiReturn(cg, ret), f.V, callArgs.ToString());
    if (types.IsVoid(ret))
        return Rvalue(types.Void, "", false);
    return Rvalue(ret, result, NeedsArc(cg, ret));
}
