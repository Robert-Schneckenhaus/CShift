// The result type of a lambda body, for inferring type arguments from lambdas: Map(2, x => x + 1) is Map<int, int>
// (docs/semantic-pass.md, step 6). It is used by the inference of code generation too, so it reports nothing, writes
// nothing to the output and leaves the function being written as it was.

namespace CShift.Check;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;
using CShift.CodeGen;

// The type of the lambda's value with these parameter types: the type of its expression, or of the first 'return x'
// of its block (void without one); 0 if it cannot be told (an error in the body, a value without a type of its own).
int LambdaResultType(Compiler cg, Expr e, int[] paramTypes)
{
    var types = cg.Types;
    var l = cg.Tree.GetLambda(e);
    if (l.Params.Length != paramTypes.Length)
        return 0;

    // the helpers of code generation write a little code: into scratch buffers (cg is a copy, so the change stays
    // here); the counters are restored, except that of the constants, whose names must stay unique
    var ir = cg.Ir;
    var savedIr = ir.S[0];
    ir.Body = StringBuilder.Create();
    ir.Allocas = StringBuilder.Create();
    ir.Preds = HashSet<string>.Create();
    cg.Ir = ir;
    // the state of the function being written: a copy, with copies of the lists that the body could change
    var saved = cg.Fn[0];
    var f = saved;
    f.Vars = List<ScopeVar>.Create();
    foreach (var v in saved.Vars)
        f.Vars.Add(v);
    f.ScopeStarts = List<int>.Create();
    foreach (var s in saved.ScopeStarts)
        f.ScopeStarts.Add(s);
    f.Temps = List<TempRelease>.Create();
    f.Loops = List<LoopCtx>.Create();
    if (saved.LambdaId > 0)
    {
        f.Captures = List<LambdaCapture>.Create();
        foreach (var c in saved.Captures)
            f.Captures.Add(c);
    }
    f.Live = true;
    f.RetType = types.Unknown;
    f.CollectReturns = true;
    f.LambdaReturn = 0;
    cg.Fn[0] = f;
    bool savedMuted = cg.St[0].Muted;
    string savedMutedError = cg.St[0].MutedError;
    cg.St[0].Muted = true;
    cg.St[0].MutedError = "";

    PushScope(cg);
    for (var i = 0; i < l.Params.Length; i += 1)
    {
        var p = l.Params[i];
        CheckNotDeclared(cg, p.Loc, p.Name);
        DeclareVar(cg, p.Name, p.Type.IsNull() ? paramTypes[i] : DeclTypeOf(cg, p.Type), "%p");
    }
    int result;
    if (!l.Block.IsNull())
    {
        CheckBlock(cg, l.Block, true);
        result = cg.Fn[0].LambdaReturn == 0 ? types.Void : cg.Fn[0].LambdaReturn;
    }
    else
        result = CheckRValue(cg, l.Body).Type;
    PopScope(cg, false);

    string error = cg.St[0].MutedError;
    cg.St[0].Muted = savedMuted;
    cg.St[0].MutedError = savedMutedError;
    cg.Fn[0] = saved;
    int globals = ir.S[0].Global;
    ir.S[0] = savedIr;
    ir.S[0].Global = globals;

    var k = types.Kind(result);
    if (types.IsUnknown(result) || k == TypeKind.Null || k == TypeKind.ErrorLit || k == TypeKind.Lambda || k == TypeKind.MethodGroup ||
        k == TypeKind.Collection)
    {
        if (error.Length > 0)
            cg.St[0].LambdaError = error; // for the message of the failed inference (TryResolveOverload)
        return 0;
    }
    return result;
}
