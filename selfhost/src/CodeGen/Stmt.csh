// Statements, scopes and function bodies (port of CodeGenStmt.cpp).

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// ---------------------------------------------------------------------------
// Scopes and cleanup
// ---------------------------------------------------------------------------

void PushScope(Compiler cg)
{
    cg.Fn[0].ScopeStarts.Add(cg.Fn[0].Vars.Count());
}

// The number of open scopes.
int ScopeCount(Compiler cg)
{
    return cg.Fn[0].ScopeStarts.Count();
}

// Releases what the variables of one scope own (in reverse order of declaration).
void EmitScopeCleanup(Compiler cg, int scope)
{
    var f = cg.Fn[0];
    int start = f.ScopeStarts.Get(scope);
    int end = scope + 1 < f.ScopeStarts.Count() ? f.ScopeStarts.Get(scope + 1) : f.Vars.Count();
    for (var i = end; i > start; i -= 1)
    {
        var v = f.Vars.Get(i - 1);
        if (v.Disposable)
            CallDispose(cg, v);
        if (v.OwnsArc && !v.IsRef)
        {
            string value = cg.Ir.Load(LlvmType(cg, v.Type), v.Slot);
            EmitRelease(cg, v.Type, value);
            if (v.ResetOnCleanup)
                cg.Ir.Store(LlvmType(cg, v.Type), ZeroValue(cg, v.Type), v.Slot);
        }
    }
}

void PopScope(Compiler cg, bool emitCleanup)
{
    var f = cg.Fn[0];
    int scope = f.ScopeStarts.Count() - 1;
    if (emitCleanup && cg.Ir.BlockOpen())
        EmitScopeCleanup(cg, scope);
    int start = f.ScopeStarts.Get(scope);
    while (f.Vars.Count() > start)
        f.Vars.RemoveAt(f.Vars.Count() - 1);
    f.ScopeStarts.RemoveAt(scope);
}

// Cleanup code for all scopes above 'depth' without popping them (used by return/break/continue).
void EmitCleanupsDownTo(Compiler cg, int depth)
{
    for (var s = ScopeCount(cg); s > depth; s -= 1)
        EmitScopeCleanup(cg, s - 1);
}

void DeclareVar(Compiler cg, string name, int type, string slot)
{
    cg.Fn[0].Vars.Add(ScopeVar { Name = name, Type = type, Slot = slot, OwnsArc = NeedsArc(cg, type) });
}

// The zero value of a type as an IR constant.
string ZeroValue(Compiler cg, int t)
{
    var types = cg.Types;
    switch (types.Kind(t))
    {
    case TypeKind.Bool: return "false";
    case TypeKind.Int:
    case TypeKind.Char:
    case TypeKind.Enum:
        return "0";
    case TypeKind.Float: return "0.0";
    case TypeKind.Error:
    case TypeKind.Optional:
    case TypeKind.Struct:
    case TypeKind.Function:
        return "zeroinitializer";
    default: return "null";
    }
}

// ---------------------------------------------------------------------------
// Function bodies
// ---------------------------------------------------------------------------

void EmitFunctionBody(Compiler cg, int instance)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var fi = cg.Instances.Get(instance);
    var d = cg.Funcs.Get(fi.Entry).Decl;

    var f = FnState { Func = instance, RetType = fi.Ret, Checked = true, File = fi.File, Env = fi.Env };
    f.Vars = List<ScopeVar>.Create();
    f.ScopeStarts = List<int>.Create();
    f.Temps = List<TempRelease>.Create();
    f.Loops = List<LoopCtx>.Create();
    f.IsIntMain = cg.St[0].MainFunc == instance + 1 && types.IsInt(fi.Ret);
    cg.Fn[0] = f;

    var sb = StringBuilder.Create();
    if (fi.HasThis)
        sb.Append("ptr %this.arg");
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        if (sb.Length() > 0)
            sb.Append(", ");
        sb.Append((fi.ParamRefs[i] != 0 ? "ptr" : AbiParam(cg, fi.ParamTypes[i])) + " %arg$" + i.ToString());
    }
    ir.BeginFunction("define internal " + AbiReturn(cg, fi.Ret) + " " + fi.LlvmName + "(" + sb.ToString() + ")");
    PushScope(cg);

    if (fi.HasThis)
    {
        string thisSlot = ir.Alloca("ptr", "this");
        ir.Store("ptr", "%this.arg", thisSlot);
        cg.Fn[0].ThisSlot = thisSlot;
    }
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        int pt = fi.ParamTypes[i];
        string name = d.Params[i].Name;
        string arg = "%arg$" + i.ToString();
        if (fi.ParamRefs[i] != 0)
        {
            string slot = ir.Alloca("ptr", name);
            ir.Store("ptr", arg, slot);
            cg.Fn[0].Vars.Add(ScopeVar { Name = name, Type = pt, Slot = slot, IsRef = true, IsConst = fi.ParamRefs[i] == 2 });
        }
        else
        {
            string slot = ir.Alloca(LlvmType(cg, pt), name);
            ir.Store(LlvmType(cg, pt), arg, slot);
            EmitRetain(cg, pt, arg); // the callee owns its copy of the parameter
            DeclareVar(cg, name, pt, slot);
        }
    }

    EmitBlock(cg, d.Body, true);

    if (ir.BlockOpen())
    {
        if (!ir.Reachable())
        {
            ir.Unreachable();
        }
        else if (types.IsVoid(fi.Ret))
        {
            EmitCleanupsDownTo(cg, 0);
            ir.Ret("void", "");
        }
        else if (IsVoidResult(cg, fi.Ret))
        {
            // Falling off the end of an Error<void> function means success.
            EmitCleanupsDownTo(cg, 0);
            ir.Ret(LlvmType(cg, fi.Ret), MakeSome(cg, fi.Ret, ""));
        }
        else
        {
            Fail(cg, d.Loc, "not all code paths of '" + fi.Name + "' return a value");
        }
    }
    ir.EndFunction();
}

void EmitBlock(Compiler cg, Stmt block, bool newScope)
{
    var b = cg.Tree.GetBlock(block);
    bool oldChecked = cg.Fn[0].Checked;
    if (b.IsUnsafe)
        cg.Fn[0].UnsafeDepth += 1;
    if (b.IsUnchecked)
        cg.Fn[0].Checked = false;
    if (newScope)
        PushScope(cg);
    foreach (var s in b.Stmts)
        EmitStmt(cg, s);
    if (newScope)
        PopScope(cg, true);
    if (b.IsUnsafe)
        cg.Fn[0].UnsafeDepth -= 1;
    cg.Fn[0].Checked = oldChecked;
}

// ---------------------------------------------------------------------------
// Statements
// ---------------------------------------------------------------------------

void EmitStmt(Compiler cg, Stmt s)
{
    cg.Ir.EnsureInsertPoint();
    switch (s.Kind)
    {
    case StmtKind.Block: EmitBlock(cg, s, true); break;
    case StmtKind.VarDecl: EmitVarDecl(cg, s); break;
    case StmtKind.Expr: EmitExprStmt(cg, s); break;
    case StmtKind.If: EmitIf(cg, s); break;
    case StmtKind.While: EmitWhile(cg, s); break;
    case StmtKind.DoWhile: EmitDoWhile(cg, s); break;
    case StmtKind.For: EmitFor(cg, s); break;
    case StmtKind.Foreach: EmitForeach(cg, s); break;
    case StmtKind.Switch: EmitSwitch(cg, s); break;
    case StmtKind.UsingBlock: EmitUsingBlock(cg, s); break;
    case StmtKind.Break: EmitBreakContinue(cg, true, s.Loc); break;
    case StmtKind.Continue: EmitBreakContinue(cg, false, s.Loc); break;
    case StmtKind.Return: EmitReturn(cg, s); break;
    case StmtKind.Empty: break;
    default:
        Fail(cg, s.Loc, "cshc does not support this kind of statement yet (" + s.Kind.ToString() + ")");
        break;
    }
}

void EmitExprStmt(Compiler cg, Stmt s)
{
    var n = cg.Tree.GetExprStmt(s);
    Value v = EmitExpr(cg, n.Expr);
    if (!v.IsLValue && v.Owned)
        HoldTemp(cg, v);
    FlushTemps(cg, 0, true);
}

void EmitVarDecl(Compiler cg, Stmt s)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var d = cg.Tree.GetVarDecl(s);
    int t = 0;
    if (!d.Type.IsNull())
        t = DeclTypeOf(cg, d.Type);
    if (t != 0 && types.IsVoid(t))
        Fail(cg, s.Loc, "variable '" + d.Name + "' cannot have type 'void'");
    if (d.IsConst)
    {
        // a local constant has no storage: its value is computed now and inlined at every use
        if (!IsConstantType(cg, t))
            Fail(cg, s.Loc, "constants can only be numbers, bool, char, string or enum values");
        var sc = ConstScope { File = cg.Fn[0].File, Locals = true, What = "constant '" + d.Name + "'", DeclLoc = s.Loc, Env = cg.Fn[0].Env };
        ConstVal cv = ConstConvert(cg, ConstEval(cg, d.Init, sc), t, d.Init.Loc, false);
        DeclareVar(cg, d.Name, t, "");
        var constVars = cg.Fn[0].Vars;
        var constVar = constVars.Get(constVars.Count() - 1);
        constVar.OwnsArc = false;
        constVar.IsConstant = true;
        constVar.ConstValue = cv;
        constVars.Set(constVars.Count() - 1, constVar);
        return;
    }

    Value init = Value { };
    if (!d.Init.IsNull())
        init = EmitExpr(cg, d.Init);
    if (t == 0)
    {
        if (d.Init.IsNull())
            Fail(cg, s.Loc, "cannot infer the type of '" + d.Name + "': 'var' needs an initializer");
        t = init.Type;
        if (types.Kind(t) == TypeKind.MethodGroup)
        {
            // 'var f = Square;' has the function type of Square if the name has a single meaning.
            t = GroupFunctionType(cg, init);
            if (t == 0)
                Fail(cg, s.Loc, "cannot infer the type of '" + d.Name + "' from the function name '" + init.GroupName +
                                "' (it is overloaded, generic or not a plain function); declare an Action/Func type");
        }
        var k = types.Kind(t);
        if (k == TypeKind.Null || k == TypeKind.ErrorLit || k == TypeKind.Void)
            Fail(cg, s.Loc, "cannot infer the type of '" + d.Name + "' from '" + types.Name(t) + "'");
    }

    if (types.IsStruct(t) && GetStructInfo(cg, t).Opaque)
        Fail(cg, s.Loc, "'" + types.Name(t) + "' is an incomplete C type and can only be used through a pointer ('" + types.Name(t) + "*')");
    string llvm = LlvmType(cg, t);
    string slot = ir.Alloca(llvm, d.Name);
    if (!d.Init.IsNull())
    {
        Value cv = ConvertValue(cg, init, t, d.Init.Loc);
        ir.Store(llvm, Consume(cg, cv), slot);
    }
    else
    {
        ir.Store(llvm, ZeroValue(cg, t), slot);
    }
    FlushTemps(cg, 0, true);
    DeclareVar(cg, d.Name, t, slot);
    if (d.IsUsing)
    {
        if (!ImplementsDisposable(cg, t))
            Fail(cg, s.Loc, "'using' requires a struct that implements IDisposable, but '" + types.Name(t) + "' does not");
        var vars = cg.Fn[0].Vars;
        var last = vars.Get(vars.Count() - 1);
        last.Disposable = true;
        vars.Set(vars.Count() - 1, last);
    }
}

void EmitIf(Compiler cg, Stmt s)
{
    var ir = cg.Ir;
    var n = cg.Tree.GetIf(s);
    PushScope(cg); // scope of pattern variables declared in the condition
    Value c = EmitCondition(cg, n.Cond);
    FlushTemps(cg, 0, true);

    string thenLabel = ir.NewLabel("if.then");
    string elseLabel = n.Else.IsNull() ? "" : ir.NewLabel("if.else");
    string endLabel = ir.NewLabel("if.end");
    ir.CondBr(c.V, thenLabel, n.Else.IsNull() ? endLabel : elseLabel);

    ir.SetBlock(thenLabel);
    EmitStmt(cg, n.Then);
    ir.Br(endLabel);

    if (!n.Else.IsNull())
    {
        ir.SetBlock(elseLabel);
        EmitStmt(cg, n.Else);
        ir.Br(endLabel);
    }
    ir.SetBlock(endLabel);
    PopScope(cg, true);
}

bool IsLiteralTrue(Compiler cg, Expr e)
{
    return !e.IsNull() && e.Kind == ExprKind.BoolLit && cg.Tree.GetBoolLit(e).Value;
}

void EmitWhile(Compiler cg, Stmt s)
{
    var ir = cg.Ir;
    var n = cg.Tree.GetWhile(s);
    string condLabel = ir.NewLabel("while.cond");
    string bodyLabel = ir.NewLabel("while.body");
    string endLabel = ir.NewLabel("while.end");
    ir.Br(condLabel);
    ir.SetBlock(condLabel);
    PushScope(cg); // pattern variables of the condition live for the whole loop

    if (IsLiteralTrue(cg, n.Cond))
    {
        ir.Br(bodyLabel);
    }
    else
    {
        Value c = EmitCondition(cg, n.Cond);
        FlushTemps(cg, 0, true);
        ir.CondBr(c.V, bodyLabel, endLabel);
    }

    ir.SetBlock(bodyLabel);
    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = endLabel, ContinueLabel = condLabel, ScopeDepth = ScopeCount(cg) });
    EmitStmt(cg, n.Body);
    cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);
    ir.Br(condLabel);

    ir.SetBlock(endLabel);
    PopScope(cg, true);
}

void EmitDoWhile(Compiler cg, Stmt s)
{
    var ir = cg.Ir;
    var n = cg.Tree.GetDoWhile(s);
    string bodyLabel = ir.NewLabel("do.body");
    string condLabel = ir.NewLabel("do.cond");
    string endLabel = ir.NewLabel("do.end");
    ir.Br(bodyLabel);
    ir.SetBlock(bodyLabel);
    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = endLabel, ContinueLabel = condLabel, ScopeDepth = ScopeCount(cg) });
    EmitStmt(cg, n.Body);
    cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);
    ir.Br(condLabel);

    ir.SetBlock(condLabel);
    Value c = EmitCondition(cg, n.Cond);
    FlushTemps(cg, 0, true);
    ir.CondBr(c.V, bodyLabel, endLabel);
    ir.SetBlock(endLabel);
}

void EmitFor(Compiler cg, Stmt s)
{
    var ir = cg.Ir;
    var n = cg.Tree.GetFor(s);
    PushScope(cg);
    if (!n.Init.IsNull())
        EmitStmt(cg, n.Init);

    string condLabel = ir.NewLabel("for.cond");
    string bodyLabel = ir.NewLabel("for.body");
    string iterLabel = ir.NewLabel("for.iter");
    string endLabel = ir.NewLabel("for.end");
    ir.Br(condLabel);
    ir.SetBlock(condLabel);
    if (!n.Cond.IsNull() && !IsLiteralTrue(cg, n.Cond))
    {
        Value c = EmitCondition(cg, n.Cond);
        FlushTemps(cg, 0, true);
        ir.CondBr(c.V, bodyLabel, endLabel);
    }
    else
    {
        ir.Br(bodyLabel);
    }

    ir.SetBlock(bodyLabel);
    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = endLabel, ContinueLabel = iterLabel, ScopeDepth = ScopeCount(cg) });
    EmitStmt(cg, n.Body);
    cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);
    ir.Br(iterLabel);

    ir.SetBlock(iterLabel);
    foreach (var it in n.Iterators)
    {
        Value v = EmitExpr(cg, it);
        if (!v.IsLValue && v.Owned)
            HoldTemp(cg, v);
        FlushTemps(cg, 0, true);
    }
    ir.Br(condLabel);

    ir.SetBlock(endLabel);
    PopScope(cg, true);
}

void EmitBreakContinue(Compiler cg, bool isBreak, SourceLoc loc)
{
    var loops = cg.Fn[0].Loops;
    for (var i = loops.Count(); i > 0; i -= 1)
    {
        var l = loops.Get(i - 1);
        if (!isBreak && l.ContinueLabel.Length == 0)
            continue;
        EmitCleanupsDownTo(cg, l.ScopeDepth);
        cg.Ir.Br(isBreak ? l.BreakLabel : l.ContinueLabel);
        return;
    }
    Fail(cg, loc, isBreak ? "'break' is only allowed inside a loop or switch" : "'continue' is only allowed inside a loop");
}

void EmitReturn(Compiler cg, Stmt s)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetReturn(s);
    int rt = cg.Fn[0].RetType;
    if (!n.Value.IsNull())
    {
        if (types.IsVoid(rt))
            Fail(cg, s.Loc, "a void function cannot return a value");
        Value v = EmitExpr(cg, n.Value);
        Value cv = ConvertValue(cg, v, rt, n.Value.Loc);
        string rv = Consume(cg, cv);
        FlushTemps(cg, 0, true);
        EmitCleanupsDownTo(cg, 0);
        ir.Ret(LlvmType(cg, rt), rv);
        return;
    }
    if (IsVoidResult(cg, rt))
    {
        // "return;" in an Error<void> function reports success.
        EmitCleanupsDownTo(cg, 0);
        ir.Ret(LlvmType(cg, rt), MakeSome(cg, rt, ""));
        return;
    }
    if (!types.IsVoid(rt))
        Fail(cg, s.Loc, "a return value of type '" + types.Name(rt) + "' is required");
    EmitCleanupsDownTo(cg, 0);
    ir.Ret("void", "");
}
