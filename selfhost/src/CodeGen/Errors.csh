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

// 'error' as a pattern type: 'x is error e' matches a failed Error<T> (unless the program declares a type 'error').
bool IsErrorPattern(Compiler cg, TypeRef t)
{
    var node = cg.Tree.GetType(t);
    if (node.Kind != TypeRefKind.Named || node.Path.Length != 1 || node.Path[0] != "error" || node.Args.Length != 0)
        return false;
    var entry = TypeDeclEntry { };
    return !LookupTypeDecl(cg, cg.Fn[0].File, "error", ref entry);
}

// The pattern type of 'x is P' / 'case P:' for a subject of type 'subject': the payload type, or - for 'error' - the
// subject itself. A pattern of the subject's own type would always match; it is an error, because it reads like a test.
int ResultPatternType(Compiler cg, int subject, TypeRef pattern, SourceLoc loc, ref bool isError)
{
    var types = cg.Types;
    isError = IsErrorPattern(cg, pattern);
    if (isError)
    {
        if (!types.IsError(subject))
            Fail(cg, loc, "'is error' needs an Error<T> value, not '" + types.Name(subject) + "'");
        return subject;
    }
    int pt = DeclTypeOf(cg, pattern);
    if (pt == subject)
        Fail(cg, loc, "a pattern of the value's own type ('" + types.Name(pt) + "') would always match; test for a failure with 'is error e' " +
                          "or for a value with 'is " + types.Name(types.Elem(subject)) + " v'");
    return pt;
}

// 'x is not P' negates a pattern. A binding ('x is not T v') is assigned where the pattern did not fail, so it is only
// allowed as the whole condition of an 'if' (see EmitIf): 'v' can then be used in the 'else' branch, and after the
// 'if' when its branch cannot complete ('if (r is not int v) return 1; Use(v);').
Value EmitIs(Compiler cg, Expr e)
{
    var n = cg.Tree.GetIs(e);
    if (n.Negated && n.BindName.Length > 0 && cg.GuardIs != e.Index)
        Fail(cg, e.Loc, "'is not' can only bind '" + n.BindName + "' as the whole condition of an 'if' (then '" + n.BindName +
                            "' is usable in the 'else' branch, and after the 'if' if its branch returns, breaks or continues)");
    cg.GuardIs = -1;
    Value v = EmitIsPattern(cg, e);
    if (!n.Negated)
        return v;
    return MakeBool(cg, cg.Ir.Bin("xor", "i1", v.V, "true"));
}

// 'x is T v' tests for a value of the payload type; 'x is error e' for a failure (e is the whole result).
Value EmitIsPattern(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetIs(e);
    Value subj = EmitRValue(cg, n.Operand);
    if (types.Kind(subj.Type) == TypeKind.Interface)
        return EmitInterfaceIs(cg, subj, DeclTypeOf(cg, n.Type), n.BindName, e.Loc);
    if (IsUnionType(cg, subj.Type))
        return EmitUnionIs(cg, subj, DeclTypeOf(cg, n.Type), n.BindName, cg.Tree.GetType(n.Type).Loc);
    if (!types.IsResultLike(subj.Type))
    {
        // 'thread is T result' (Thread<T> only): matches the Optional<T> of _TryGetResult() (stdlib/thread.csh), a value
        // only once the thread has completed without being cancelled.
        var sd = types.IsStruct(subj.Type) ? cg.Structs.Get(GetStructInfo(cg, subj.Type).Entry).Decl : StructDecl { };
        if (types.IsStruct(subj.Type) && sd.Name == "Thread" && sd.TypeParams.Length > 0)
        {
            HoldTemp(cg, subj);
            string thisPtr = ir.Alloca(LlvmType(cg, subj.Type), "tmp");
            ir.Store(LlvmType(cg, subj.Type), subj.V, thisPtr);
            subj = EmitDirectCall(cg, ThreadMethod(cg, subj.Type, "_TryGetResult", e.Loc), thisPtr, new Arg[0], e.Loc);
        }
        else
        {
            string shown = types.IsStruct(subj.Type) && sd.Name == "_ThreadVoid" ? "Thread" : types.Name(subj.Type);
            Fail(cg, e.Loc, "'is' can only be used with Error<T>, Optional<T> and Thread<T> values, not '" + shown + "'");
        }
    }
    bool isErrorPattern = false;
    int pattern = ResultPatternType(cg, subj.Type, n.Type, cg.Tree.GetType(n.Type).Loc, ref isErrorPattern);
    if (types.IsError(subj.Type) && types.IsOptional(types.Elem(subj.Type)) && pattern == types.Elem(types.Elem(subj.Type)))
    {
        // Error<Optional<T>> is T v: succeeded and has a value. The subject becomes its Optional<T> (empty on error).
        HoldTemp(cg, subj);
        int optional = types.Elem(subj.Type);
        string ok = ir.ExtractValue(LlvmType(cg, subj.Type), subj.V, "0");
        string inner = ir.ExtractValue(LlvmType(cg, subj.Type), subj.V, "1");
        subj = Rvalue(optional, ir.Select(ok, LlvmType(cg, optional), inner, "zeroinitializer"), false);
    }
    bool whole = pattern == subj.Type;
    if (!whole && pattern != types.Elem(subj.Type))
        Fail(cg, cg.Tree.GetType(n.Type).Loc, "pattern type '" + types.Name(pattern) + "' does not match the payload type '" +
                                              types.Name(types.Elem(subj.Type)) + "' of '" + types.Name(subj.Type) + "'");

    string subjIr = LlvmType(cg, subj.Type);
    string flag = whole ? ir.Bin("xor", "i1", ir.ExtractValue(subjIr, subj.V, "0"), "true") : ir.ExtractValue(subjIr, subj.V, "0");
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
