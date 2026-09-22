// Error<T> and Optional<T>: construction, 'is' patterns, 'try' and the error literal (the result parts of
// CodeGenExpr.cpp and CodeGenRuntime.cpp).
//
// Error<T>     { i1 ok, T value, ptr message, i32 code }
// Optional<T>  { i1 has value, T value }
// error("..")  { ptr message, i32 code }   (the type of an error literal before it is converted)

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// A result that holds a value; 'payload' is empty for Error<void>.
string MakeSome(Compiler cg, int resultType, string payloadOwned)
{
    string ty = LlvmType(cg, resultType);
    string agg = cg.Ir.InsertValue(ty, "zeroinitializer", "i1", "true", "0");
    if (payloadOwned.Length == 0)
        return agg;
    return cg.Ir.InsertValue(ty, agg, LlvmType(cg, cg.Types.Elem(resultType)), payloadOwned, "1");
}

string MakeErr(Compiler cg, int errorType, string msgOwned, string code)
{
    string ty = LlvmType(cg, errorType);
    string agg = cg.Ir.InsertValue(ty, "zeroinitializer", "ptr", msgOwned, "2");
    return cg.Ir.InsertValue(ty, agg, "i32", code, "3");
}

bool IsVoidResult(Compiler cg, int t)
{
    return cg.Types.IsError(t) && cg.Types.IsVoid(cg.Types.Elem(t));
}

// The handle of stderr in the current function.
string StderrHandle(Compiler cg)
{
    if (cg.St[0].Windows)
        return cg.Ir.Call("ptr", "@__acrt_iob_func", "i32 2");
    return cg.Ir.Load("ptr", "@stderr");
}

// error("message") or error("message", code)
Value EmitErrorLit(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetErrorLit(e);
    Value msg = ConvertValue(cg, EmitRValue(cg, n.Message), types.String, n.Message.Loc);
    string code = "0";
    if (!n.Code.IsNull())
        code = ConvertValue(cg, EmitRValue(cg, n.Code), types.I32, n.Code.Loc).V;
    string owned = Consume(cg, msg);
    string ty = LlvmType(cg, types.ErrorLit);
    string agg = ir.InsertValue(ty, "zeroinitializer", "ptr", owned, "0");
    agg = ir.InsertValue(ty, agg, "i32", code, "1");
    return Rvalue(types.ErrorLit, agg, true);
}

// 'x is T v' tests for a value of the payload type; 'x is Error<T> r' always matches and binds the whole result.
Value EmitIs(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetIs(e);
    Value subj = EmitRValue(cg, n.Operand);
    if (!types.IsResultLike(subj.Type))
        Fail(cg, e.Loc, "'is' can only be used with Error<T> and Optional<T> values, not '" + types.Name(subj.Type) + "'");
    int pattern = DeclTypeOf(cg, n.Type);
    bool whole = pattern == subj.Type;
    if (!whole && pattern != types.Elem(subj.Type))
        Fail(cg, cg.Tree.GetType(n.Type).Loc, "pattern type '" + types.Name(pattern) + "' does not match the payload type '" +
                                              types.Name(types.Elem(subj.Type)) + "' of '" + types.Name(subj.Type) + "'");

    string subjIr = LlvmType(cg, subj.Type);
    string flag = whole ? "true" : ir.ExtractValue(subjIr, subj.V, "0");
    if (n.BindName.Length > 0)
    {
        // The payload is zero when there is no value, so the binding is unconditionally assigned.
        string payload = whole ? subj.V : ir.ExtractValue(subjIr, subj.V, "1");
        string patternIr = LlvmType(cg, pattern);
        string slot = ir.Alloca(patternIr, n.BindName);
        ir.Allocas.Append("  store " + patternIr + " " + ZeroValue(cg, pattern) + ", ptr " + slot + "\n");
        DeclareVar(cg, n.BindName, pattern, slot);
        var vars = cg.Fn[0].Vars;
        var last = vars.Get(vars.Count() - 1);
        last.ResetOnCleanup = true;
        vars.Set(vars.Count() - 1, last);
        if (NeedsArc(cg, pattern) && !subj.Owned)
            EmitRetain(cg, pattern, payload);
        // If the subject was an owned temporary, its payload reference moves into the binding.
        StoreSlot(cg, pattern, slot, payload, true);
        if (subj.Owned && NeedsArc(cg, subj.Type) && !whole)
        {
            // Release what remains of the subject (the error message); the payload moved out.
            if (types.IsError(subj.Type))
                EmitRelease(cg, types.String, ir.ExtractValue(subjIr, subj.V, "2"));
        }
    }
    else
    {
        HoldTemp(cg, subj);
    }
    return MakeBool(cg, flag);
}

// 'try x': the value of an Error<T>, or return the error from the current function.
Value EmitTry(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetTry(e);
    Value subj = EmitRValue(cg, n.Operand);
    if (!types.IsError(subj.Type))
        Fail(cg, e.Loc, "'try' can only be used with Error<T> values, not '" + types.Name(subj.Type) + "'");
    bool intMain = cg.Fn[0].IsIntMain;
    int retType = cg.Fn[0].RetType;
    if (!types.IsError(retType) && !intMain)
        Fail(cg, e.Loc, "'try' can only be used in a function that returns Error<T>");

    string subjIr = LlvmType(cg, subj.Type);
    string flag = ir.ExtractValue(subjIr, subj.V, "0");
    string okLabel = ir.NewLabel("try.ok");
    string failLabel = ir.NewLabel("try.fail");
    ir.CondBr(flag, okLabel, failLabel);

    ir.SetBlock(failLabel);
    string msg = ir.ExtractValue(subjIr, subj.V, "2");
    string code = ir.ExtractValue(subjIr, subj.V, "3");
    if (!subj.Owned)
        EmitRetain(cg, types.String, msg); // the returned error owns its message
    // Release temporaries of the current statement and all live locals, then return.
    FlushTemps(cg, 0, false);
    EmitCleanupsDownTo(cg, 0);
    if (intMain)
    {
        string text = ir.Call("ptr", "@__cs_data", "ptr " + msg);
        ir.CallVariadic("i32", "ptr, ptr", "@fprintf", "ptr " + StderrHandle(cg) + ", ptr " + ir.CString("error: %s\n") + ", ptr " + text);
        ir.Ret(LlvmType(cg, retType), "1");
    }
    else
    {
        ir.Ret(LlvmType(cg, retType), MakeErr(cg, retType, msg, code));
    }

    ir.SetBlock(okLabel);
    int elem = types.Elem(subj.Type);
    if (types.IsVoid(elem))
        return Rvalue(types.Void, "", false);
    string payload = ir.ExtractValue(subjIr, subj.V, "1");
    return Rvalue(elem, payload, subj.Owned && NeedsArc(cg, elem));
}

// ---------------------------------------------------------------------------
// Reference counting of the aggregates
// ---------------------------------------------------------------------------

// __retain.<T> / __release.<T> of Error<T>, Optional<T> and error literals: the members that hold references.
string ResultHelper(Compiler cg, int t, bool isRetain)
{
    var types = cg.Types;
    var ir = cg.Ir;
    string name = "@\"" + (isRetain ? "__retain." : "__release.") + types.Name(t) + "\"";
    if (!ir.Declared.Add(name))
        return name;
    string ty = LlvmType(cg, t);
    var sb = StringBuilder.Create();
    sb.Append("define internal void " + name + "(" + ty + " %v) {\nentry:\n");
    int n = 0;
    if (types.Kind(t) == TypeKind.ErrorLit)
    {
        sb.Append(MemberHelperCall(cg, types.String, 0, n, isRetain, ty));
    }
    else
    {
        int elem = types.Elem(t);
        if (NeedsArc(cg, elem))
        {
            sb.Append(MemberHelperCall(cg, elem, 1, n, isRetain, ty));
            n += 1;
        }
        if (types.IsError(t))
            sb.Append(MemberHelperCall(cg, types.String, 2, n, isRetain, ty));
    }
    sb.Append("  ret void\n}\n\n");
    ir.AppendHelper(sb.ToString());
    return name;
}
