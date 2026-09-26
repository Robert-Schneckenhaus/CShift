// Lambdas and closures (only in the self-hosted compiler).
//
//     Func<int, int> add = x => x + offset;       // captures 'offset'
//     list.ForEach(item => Console.WriteLine(item));
//
// A lambda has no type of its own: it is compiled when it is converted to an Action/Func type, which gives the types of
// its parameters and result. Its body becomes a function of its own; the variables of the enclosing functions that it
// uses are captured *by value* when the lambda is created (a copy, like C++'s [=]) and are read-only inside it. In a
// method, the lambda works on a copy of the struct ('this').
//
// The body is compiled right away, into an IR writer of its own; the enclosing variables it needs are found while it is
// compiled (LookupVariable asks CaptureVariable). Only then the environment is known: the block
// { i64 count, i64 unused, ptr drop, captured values..., [this] } that the new function value owns (see FuncPtrs.csh).
// A lambda that captures nothing is a plain function (no environment, and it can be passed to C).

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// Can the lambda be converted to the function type? (the number of parameters and the written parameter types)
int LambdaConversionCost(Compiler cg, Value v, int to)
{
    var types = cg.Types;
    int target = types.IsCFunction(to) ? types.Elem(to) : to;
    if (!types.IsFunction(target))
        return -1;
    var n = cg.Tree.GetLambda(v.LambdaNode);
    var ptypes = types.Params(target);
    if (n.Params.Length != ptypes.Length)
        return -1;
    for (var i = 0; i < n.Params.Length; i += 1)
    {
        if (!n.Params[i].Type.IsNull() && ResolveValueType(cg, n.Params[i].Type.Id, cg.Fn[0].File, cg.Fn[0].Env) != ptypes[i])
            return -1;
    }
    return 1;
}

// The variable of an enclosing function that the body of a lambda uses: an entry of the environment (read-only).
Value CaptureVariable(Compiler cg, string name)
{
    var f = cg.Fn[0];
    for (var i = 0; i < f.Captures.Count(); i += 1)
    {
        if (f.Captures.Get(i).Name == name)
            return Lvalue(f.Captures.Get(i).Type, EnvField(cg, 3 + i), true);
    }
    for (var i = f.Outer.Count(); i > 0; i -= 1)
    {
        var v = f.Outer.Get(i - 1);
        if (v.Name != name)
            continue;
        if (v.IsConstant)
            return ConstToValue(cg, v.ConstValue);
        f.Captures.Add(LambdaCapture { Name = name, Type = v.Type });
        return Lvalue(v.Type, EnvField(cg, 3 + f.Captures.Count() - 1), true);
    }
    return Value { };
}

// Is the name a variable of an enclosing function (without capturing it)?
bool IsOuterName(Compiler cg, string name)
{
    var f = cg.Fn[0];
    if (f.LambdaId == 0)
        return false;
    foreach (var c in f.Captures)
    {
        if (c.Name == name)
            return true;
    }
    foreach (var v in f.Outer)
    {
        if (v.Name == name)
            return true;
    }
    return false;
}

string EnvField(Compiler cg, int index)
{
    return cg.Ir.Gep(cg.Fn[0].EnvType, "%lambda.env", "i32 0, i32 " + index.ToString());
}

// Compiles the lambda as a value of the function type 'ft'.
Value EmitLambda(Compiler cg, Expr e, int ft, SourceLoc loc)
{
    var types = cg.Types;
    var n = cg.Tree.GetLambda(e);
    var ptypes = types.Params(ft);
    int ret = types.Elem(ft);
    if (n.Params.Length != ptypes.Length)
        Fail(cg, loc, "the lambda has " + n.Params.Length.ToString() + " parameter(s), '" + types.Name(ft) + "' needs " +
                          ptypes.Length.ToString());
    for (var i = 0; i < n.Params.Length; i += 1)
    {
        if (n.Params[i].Type.IsNull())
            continue;
        int written = ResolveValueType(cg, n.Params[i].Type.Id, cg.Fn[0].File, cg.Fn[0].Env);
        if (written != ptypes[i])
            Fail(cg, n.Params[i].Loc, "parameter '" + n.Params[i].Name + "' of the lambda has type '" + types.Name(written) + "', but '" +
                                          types.Name(ft) + "' needs '" + types.Name(ptypes[i]) + "'");
    }

    cg.St[0].LambdaCount += 1;
    string id = cg.St[0].LambdaCount.ToString();
    var outerState = cg.Fn[0];
    var outerFi = cg.Instances.Get(outerState.Func);
    string fnName = "@\"lambda." + id + "\"";
    string envType = "%\"lambda." + id + ".env\"";

    // the function instance of the lambda (for the call graph: purity of threads, order of global initializers)
    var fi = FuncInfo { Entry = outerFi.Entry, File = outerState.File, Owner = outerFi.Owner, Env = outerState.Env,
                        Name = outerFi.Name + ".lambda" + id, Ret = ret, HasThis = false, LlvmName = fnName,
                        SignatureResolved = true, Queued = true };
    fi.ParamTypes = ptypes;
    fi.ParamRefs = new int[ptypes.Length];
    cg.Instances.Add(fi);
    int instance = cg.Instances.Count() - 1;

    // what the body can see of the enclosing functions
    var outer = List<ScopeVar>.Create();
    if (outerState.LambdaId > 0)
    {
        foreach (var v in outerState.Outer)
            outer.Add(v);
    }
    foreach (var v in outerState.Vars)
        outer.Add(v);
    bool thisAvailable = outerState.ThisSlot != null && outerState.ThisSlot.Length > 0;

    // an IR writer of its own (the constants, declarations and helpers are shared)
    var sub = cg.Ir;
    sub.S = new IrState[1];
    sub.S[0] = cg.Ir.S[0];
    sub.Body = StringBuilder.Create();
    sub.Allocas = StringBuilder.Create();
    sub.Preds = HashSet<string>.Create();
    sub.Functions = StringBuilder.Create();
    var lcg = cg;
    lcg.Ir = sub;

    var f = FnState { Func = instance, RetType = ret, Checked = outerState.Checked, UnsafeDepth = outerState.UnsafeDepth,
                      File = outerState.File, Env = outerState.Env, LambdaId = cg.St[0].LambdaCount, EnvType = envType };
    f.Vars = List<ScopeVar>.Create();
    f.ScopeStarts = List<int>.Create();
    f.Temps = List<TempRelease>.Create();
    f.Loops = List<LoopCtx>.Create();
    f.Outer = outer;
    f.Captures = List<LambdaCapture>.Create();
    f.ThisSlot = thisAvailable ? "%this.cap" : "";
    cg.Fn[0] = f;

    var header = StringBuilder.Create();
    header.Append("ptr %lambda.env");
    for (var i = 0; i < ptypes.Length; i += 1)
        header.Append(", " + AbiParam(lcg, ptypes[i]) + " %arg$" + i.ToString());
    sub.BeginFunction("define internal " + AbiReturn(lcg, ret) + " " + fnName + "(" + header.ToString() + ")");
    PushScope(lcg);
    for (var i = 0; i < ptypes.Length; i += 1)
    {
        string slot = sub.Alloca(LlvmType(lcg, ptypes[i]), n.Params[i].Name);
        sub.Store(LlvmType(lcg, ptypes[i]), "%arg$" + i.ToString(), slot);
        EmitRetain(lcg, ptypes[i], "%arg$" + i.ToString()); // the callee owns its copy of the parameter
        DeclareVar(lcg, n.Params[i].Name, ptypes[i], slot);
    }

    if (n.Block.Kind != StmtKind.None)
    {
        EmitBlock(lcg, n.Block, true);
        if (sub.BlockOpen())
        {
            if (!sub.Reachable())
                sub.Unreachable();
            else if (types.IsVoid(ret))
            {
                EmitCleanupsDownTo(lcg, 0);
                sub.Ret("void", "");
            }
            else if (IsVoidResult(lcg, ret))
            {
                EmitCleanupsDownTo(lcg, 0);
                sub.Ret(LlvmType(lcg, ret), MakeSome(lcg, ret, ""));
            }
            else
                Fail(cg, loc, "not all code paths of the lambda return a value");
        }
    }
    else if (types.IsVoid(ret))
    {
        Value v = EmitExpr(lcg, n.Body);
        if (!v.IsLValue && v.Owned)
            HoldTemp(lcg, v);
        FlushTemps(lcg, 0, true);
        EmitCleanupsDownTo(lcg, 0);
        sub.Ret("void", "");
    }
    else
    {
        Value v = ConvertValue(lcg, EmitExpr(lcg, n.Body), ret, n.Body.Loc);
        string rv = Consume(lcg, v);
        FlushTemps(lcg, 0, true);
        EmitCleanupsDownTo(lcg, 0);
        sub.Ret(LlvmType(lcg, ret), rv);
    }
    sub.EndFunction();

    var captures = cg.Fn[0].Captures;
    cg.Fn[0] = outerState;
    cg.Ir.S[0].Global = sub.S[0].Global;
    cg.Ir.S[0].Label = sub.S[0].Label;

    string text = sub.Functions.ToString();
    bool capturesThis = thisAvailable && text.Contains("%this.cap");
    bool hasEnv = captures.Count() > 0 || capturesThis;
    int ownerType = outerFi.Owner;
    if (!hasEnv)
    {
        // a plain function: no environment parameter
        text = text.Replace("(ptr %lambda.env, ", "(").Replace("(ptr %lambda.env)", "()");
    }
    else if (capturesThis)
    {
        // the copy of 'this' is the last entry of the environment
        string thisField = "  %this.cap = alloca ptr\n  %this.field = getelementptr " + envType + ", ptr %lambda.env, i32 0, i32 " +
                           (3 + captures.Count()).ToString() + "\n  store ptr %this.field, ptr %this.cap\n";
        int entry = text.IndexOf("entry:\n");
        text = text.Substring(0, entry + 7) + thisField + text.Substring(entry + 7);
    }
    cg.Ir.AppendHelper(text);
    NoteCall(cg, instance);
    if (!hasEnv)
        return Rvalue(ft, "{ ptr " + fnName + ", ptr null }", false);

    // the environment type and its drop function (releases the captured values)
    var fields = StringBuilder.Create();
    fields.Append("i64, i64, ptr");
    foreach (var c in captures)
        fields.Append(", " + LlvmType(cg, c.Type));
    if (capturesThis)
        fields.Append(", " + LlvmType(cg, ownerType));
    cg.Ir.Globals.Append(envType + " = type { " + fields.ToString() + " }\n");
    var drop = StringBuilder.Create();
    drop.Append("define internal void @\"lambda." + id + ".drop\"(ptr %env) {\nentry:\n");
    int count = captures.Count() + (capturesThis ? 1 : 0);
    for (var i = 0; i < count; i += 1)
    {
        int t = i < captures.Count() ? captures.Get(i).Type : ownerType;
        if (!NeedsArc(cg, t))
            continue;
        string index = (3 + i).ToString();
        drop.Append("  %p" + index + " = getelementptr " + envType + ", ptr %env, i32 0, i32 " + index + "\n");
        drop.Append("  %v" + index + " = load " + LlvmType(cg, t) + ", ptr %p" + index + "\n");
        drop.Append("  call void " + ReleaseFunction(cg, t) + "(" + LlvmType(cg, t) + " %v" + index + ")\n");
    }
    drop.Append("  ret void\n}\n");
    cg.Ir.AppendHelper(drop.ToString());

    // creating the value: a new environment with copies of the captured values
    var ir = cg.Ir;
    string size = ir.Bin("sub", "i64", "ptrtoint (ptr getelementptr (" + envType + ", ptr null, i32 1) to i64)", "16");
    string env = ir.Call("ptr", "@__cs_alloc", "i64 " + size + ", i64 0");
    ir.Store("ptr", "@\"lambda." + id + ".drop\"", ir.Gep(envType, env, "i32 0, i32 2"));
    for (var i = 0; i < captures.Count(); i += 1)
    {
        var c = captures.Get(i);
        Value v = LookupVariable(cg, c.Name); // in a lambda inside a lambda this captures it there as well
        string copy = Consume(cg, ToRValue(cg, v));
        ir.Store(LlvmType(cg, c.Type), copy, ir.Gep(envType, env, "i32 0, i32 " + (3 + i).ToString()));
    }
    if (capturesThis)
    {
        Value self = ThisValue(cg, loc);
        string copy = Consume(cg, ToRValue(cg, self));
        ir.Store(LlvmType(cg, ownerType), copy, ir.Gep(envType, env, "i32 0, i32 " + (3 + captures.Count()).ToString()));
    }
    string value = ir.InsertValue("{ ptr, ptr }", "{ ptr " + fnName + ", ptr null }", "ptr", env, "1");
    return Rvalue(ft, value, true);
}
