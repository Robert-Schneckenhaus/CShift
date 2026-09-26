// Function values: Action<...> and Func<..., R>.
//
// A function value is { ptr fn, ptr env }. For a plain function (and a lambda that captures nothing) env is null and
// fn is the function itself, so it can be passed to C as it is. A lambda that captures variables (Lambdas.csh) has an
// environment: a reference-counted block { i64 count, i64 unused, ptr drop, captured values... }, and fn takes it as
// an extra first parameter. 'drop' releases the captured values when the last reference goes away.
//
// A function name used as a value has the type "function" (a method group). It becomes a function value when it is
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
        if (d.IsThread)
        {
            reason = "'" + g.GroupName + "' is a 'thread' function and cannot be used as a function pointer (use 'start " + g.GroupName +
                     "(...)' to start it)";
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
    if (fi.HasThis || d.IsVariadic || d.RetOut || d.RetCString || d.IsThread)
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
    return Rvalue(to, "{ ptr " + cg.Instances.Get(instance).LlvmName + ", ptr null }", false);
}

// The plain function pointer of a function value for C; a closure (with an environment) cannot be called by C.
string RawFunctionPointer(Compiler cg, string value)
{
    var ir = cg.Ir;
    string env = ir.ExtractValue("{ ptr, ptr }", value, "1");
    EmitPanicIf(cg, ir.ICmp("ne", "ptr", env, "null"), "a lambda that captures variables cannot be passed to C");
    return ir.ExtractValue("{ ptr, ptr }", value, "0");
}

string FunctionRetainHelper(Compiler cg)
{
    string name = "@__cs_retain_fn";
    if (cg.Ir.Declared.Add(name))
        cg.Ir.AppendHelper("define internal void @__cs_retain_fn({ ptr, ptr } %f) {\nentry:\n" +
                           "  %env = extractvalue { ptr, ptr } %f, 1\n  call void @__cs_retain(ptr %env)\n  ret void\n}\n");
    return name;
}

// Releases the environment of a function value: the last reference calls its 'drop' function (which releases the
// captured values) and frees the block.
string FunctionReleaseHelper(Compiler cg)
{
    string name = "@__cs_release_fn";
    if (cg.Ir.Declared.Add(name))
        cg.Ir.AppendHelper("define internal void @__cs_release_fn({ ptr, ptr } %f) {\nentry:\n" +
                           "  %env = extractvalue { ptr, ptr } %f, 1\n" +
                           "  %isnull = icmp eq ptr %env, null\n  br i1 %isnull, label %done, label %dec\n" +
                           "dec:\n  %rc = load i64, ptr %env\n  %rc1 = sub i64 %rc, 1\n  store i64 %rc1, ptr %env\n" +
                           "  %last = icmp eq i64 %rc1, 0\n  br i1 %last, label %drop, label %done\n" +
                           "drop:\n  %dropp = getelementptr i8, ptr %env, i64 16\n  %dropfn = load ptr, ptr %dropp\n" +
                           "  call void %dropfn(ptr %env)\n  call void @free(ptr %env)\n" +
                           (cg.St[0].ArcStats ? "  %fr = atomicrmw add ptr @__cs_frees, i64 1 monotonic\n" : "") +
                           "  br label %done\n" +
                           "done:\n  ret void\n}\n");
    return name;
}

// A call through a function pointer.
Value EmitIndirectCall(Compiler cg, Value callee, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value f = ToRValue(cg, callee);
    if (cg.Types.IsCFunction(f.Type))
        f = ConvertValue(cg, f, cg.Types.Elem(f.Type), loc);
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

    // fn(args) for a plain function, fn(env, args) for a closure
    HoldTemp(cg, f);
    string fn = ir.ExtractValue("{ ptr, ptr }", f.V, "0");
    string env = ir.ExtractValue("{ ptr, ptr }", f.V, "1");
    EmitPanicIf(cg, ir.ICmp("eq", "ptr", fn, "null"), "call of a null function");
    int ret = types.Elem(ft);
    string retAbi = AbiReturn(cg, ret);
    string plainLabel = ir.NewLabel("call.plain");
    string closureLabel = ir.NewLabel("call.closure");
    string endLabel = ir.NewLabel("call.end");
    ir.CondBr(ir.ICmp("eq", "ptr", env, "null"), plainLabel, closureLabel);
    ir.SetBlock(plainLabel);
    string plainResult = ir.Call(retAbi, fn, callArgs.ToString());
    ir.Br(endLabel);
    ir.SetBlock(closureLabel);
    string closureResult = ir.Call(retAbi, fn, "ptr " + env + (callArgs.Length() > 0 ? ", " + callArgs.ToString() : ""));
    ir.Br(endLabel);
    ir.SetBlock(endLabel);
    if (types.IsVoid(ret))
        return Rvalue(types.Void, "", false);
    string result = ir.Phi(LlvmType(cg, ret), "[ " + plainResult + ", %" + plainLabel + " ], [ " + closureResult + ", %" + closureLabel + " ]");
    return Rvalue(ret, result, NeedsArc(cg, ret));
}

// Values that can be called: Action/Func and the function pointer fields of C structs.
bool IsCallableType(Compiler cg, int t)
{
    return cg.Types.IsFunction(t) || cg.Types.IsCFunction(t);
}
