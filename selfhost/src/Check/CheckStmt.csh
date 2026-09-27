// The checker for statements. The scopes open and close where code generation opens and closes them (CodeGen/Stmt.csh),
// so that a name means the same in both.

namespace CShift.Check;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.CodeGen;

void CheckStmt(Compiler cg, Stmt s)
{
    switch (s.Kind)
    {
    case StmtKind.Block: CheckBlock(cg, s, true); break;
    case StmtKind.VarDecl: CheckVarDecl(cg, s); break;
    case StmtKind.Expr: CheckExpr(cg, cg.Tree.GetExprStmt(s).Expr); break;
    case StmtKind.If: CheckIf(cg, s); break;
    case StmtKind.While:
    {
        var n = cg.Tree.GetWhile(s);
        PushScope(cg); // pattern variables of the condition live for the whole loop
        if (!IsLiteralTrue(cg, n.Cond))
            CheckCondition(cg, n.Cond);
        CheckLoopBody(cg, n.Body, true);
        PopScope(cg, false);
        break;
    }
    case StmtKind.DoWhile:
    {
        var n = cg.Tree.GetDoWhile(s);
        CheckLoopBody(cg, n.Body, true);
        CheckCondition(cg, n.Cond);
        break;
    }
    case StmtKind.For:
    {
        var n = cg.Tree.GetFor(s);
        PushScope(cg);
        if (!n.Init.IsNull())
            CheckStmt(cg, n.Init);
        if (!n.Cond.IsNull() && !IsLiteralTrue(cg, n.Cond))
            CheckCondition(cg, n.Cond);
        CheckLoopBody(cg, n.Body, true);
        foreach (var it in n.Iterators)
            CheckExpr(cg, it);
        PopScope(cg, false);
        break;
    }
    case StmtKind.Foreach: CheckForeach(cg, s); break;
    case StmtKind.Switch: CheckSwitch(cg, s); break;
    case StmtKind.UsingBlock:
    {
        var n = cg.Tree.GetUsingBlock(s);
        PushScope(cg);
        CheckStmt(cg, n.Decl);
        CheckStmt(cg, n.Body);
        PopScope(cg, false);
        break;
    }
    case StmtKind.Break:
    case StmtKind.Continue:
        CheckBreakContinue(cg, s.Kind == StmtKind.Break, s.Loc);
        break;
    case StmtKind.Return: CheckReturn(cg, s); break;
    default:
        break;
    }
}

void CheckBlock(Compiler cg, Stmt block, bool newScope)
{
    var b = cg.Tree.GetBlock(block);
    if (b.IsUnsafe)
        cg.Fn[0].UnsafeDepth += 1;
    if (newScope)
        PushScope(cg);
    foreach (var s in b.Stmts)
        CheckStmt(cg, s);
    if (newScope)
        PopScope(cg, false);
    if (b.IsUnsafe)
        cg.Fn[0].UnsafeDepth -= 1;
}

// The body of a loop: 'break' and 'continue' are allowed in it.
void CheckLoopBody(Compiler cg, Stmt body, bool canContinue)
{
    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = "break", ContinueLabel = canContinue ? "continue" : "", ScopeDepth = ScopeCount(cg) });
    CheckStmt(cg, body);
    cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);
}

void CheckBreakContinue(Compiler cg, bool isBreak, SourceLoc loc)
{
    var loops = cg.Fn[0].Loops;
    for (var i = 0; i < loops.Count(); i += 1)
    {
        if (isBreak || loops.Get(i).ContinueLabel.Length > 0)
            return;
    }
    CheckError(cg, loc, isBreak ? "'break' is only allowed inside a loop or switch" : "'continue' is only allowed inside a loop");
}

// A condition must be a bool (see EmitCondition).
void CheckCondition(Compiler cg, Expr e)
{
    Value v = CheckRValue(cg, e);
    string why = ConditionError(cg, v.Type);
    if (why.Length > 0)
        CheckError(cg, e.Loc, why);
}

// 'if (x is not T v)' binds v in the enclosing scope, not visible in the 'if' branch (see EmitIf). After the 'if' it is
// visible here in any case (code generation hides it where the 'if' branch can complete).
void CheckIf(Compiler cg, Stmt s)
{
    var n = cg.Tree.GetIf(s);
    bool guard = n.Cond.Kind == ExprKind.Is && cg.Tree.GetIs(n.Cond).Negated && cg.Tree.GetIs(n.Cond).BindName.Length > 0;
    if (!guard)
        PushScope(cg);
    CheckCondition(cg, n.Cond);
    int bound = cg.Fn[0].Vars.Count() - 1;
    if (guard && bound >= 0)
        SetVarVisible(cg, bound, false);
    CheckBranch(cg, n.Then);
    if (guard && bound >= 0)
        SetVarVisible(cg, bound, true);
    if (!n.Else.IsNull())
        CheckBranch(cg, n.Else);
    if (!guard)
        PopScope(cg, false);
}

void CheckBranch(Compiler cg, Stmt s)
{
    PushScope(cg);
    CheckStmt(cg, s);
    PopScope(cg, false);
}

void CheckVarDecl(Compiler cg, Stmt s)
{
    var types = cg.Types;
    var d = cg.Tree.GetVarDecl(s);
    int t = 0;
    if (!d.Type.IsNull())
        t = DeclTypeOf(cg, d.Type);
    if (d.IsConst)
    {
        // a local constant: its value is computed by the constant evaluator, like in code generation
        if (!IsConstantType(cg, t))
            FailConstantType(cg, s.Loc, t);
        var sc = ConstScope { File = cg.Fn[0].File, Locals = true, What = "constant '" + d.Name + "'", DeclLoc = s.Loc, Env = cg.Fn[0].Env };
        ConstVal cv = IsEmbedExpr(d.Init) ? ConstEmbed(cg, d.Init, t) : ConstConvert(cg, ConstEval(cg, d.Init, sc), t, d.Init.Loc, false);
        DeclareVar(cg, d.Name, t, "");
        var vars = cg.Fn[0].Vars;
        var constVar = vars.Get(vars.Count() - 1);
        constVar.IsConstant = true;
        constVar.ConstValue = cv;
        vars.Set(vars.Count() - 1, constVar);
        return;
    }
    if (t != 0 && types.IsVoid(t))
    {
        CheckError(cg, s.Loc, "variable '" + d.Name + "' cannot have type 'void'");
        t = types.Unknown;
    }
    Value init = Value { };
    if (!d.Init.IsNull())
        init = CheckExpr(cg, d.Init);
    if (t == 0)
    {
        if (d.Init.IsNull())
        {
            CheckError(cg, s.Loc, "cannot infer the type of '" + d.Name + "': 'var' needs an initializer");
            t = types.Unknown;
        }
        else
        {
            string why = "";
            t = VarTypeFromInit(cg, init, d.Name, ref why);
            if (t == 0)
            {
                CheckError(cg, s.Loc, why);
                t = types.Unknown;
            }
        }
    }
    else if (!d.Init.IsNull())
        CheckConversion(cg, init, t, d.Init.Loc);
    DeclareVar(cg, d.Name, t, "%v");
}

// Reports if the value does not convert implicitly to the type (see ConvertValue).
void CheckConversion(Compiler cg, Value v, int to, SourceLoc loc)
{
    var types = cg.Types;
    if (IsUnknown(cg, v) || types.IsUnknown(to))
        return;
    var k = types.Kind(v.Type);
    // lambdas, function names and collection expressions are converted by code generation for now
    if (k == TypeKind.Lambda || k == TypeKind.MethodGroup || k == TypeKind.Collection || types.IsCFunction(to) || IsUnionType(cg, to))
        return;
    string why = ConversionError(cg, v, to);
    if (why.Length > 0)
        CheckError(cg, loc, why);
}

void CheckReturn(Compiler cg, Stmt s)
{
    var types = cg.Types;
    var n = cg.Tree.GetReturn(s);
    int rt = cg.Fn[0].RetType;
    if (!n.Value.IsNull())
    {
        if (types.IsVoid(rt))
        {
            CheckError(cg, s.Loc, "a void function cannot return a value");
            CheckExpr(cg, n.Value);
            return;
        }
        CheckConversion(cg, CheckExpr(cg, n.Value), rt, n.Value.Loc);
        return;
    }
    if (!types.IsVoid(rt) && !IsVoidResult(cg, rt))
        CheckError(cg, s.Loc, "a return value of type '" + types.Name(rt) + "' is required");
}

// foreach: the loop variable has the element type (see EmitForeach); structs with Count() and Get(int) are left to
// code generation for now.
void CheckForeach(Compiler cg, Stmt s)
{
    var types = cg.Types;
    var n = cg.Tree.GetForeach(s);
    Value it = CheckRValue(cg, n.Iterable);
    int coll = it.Type;
    int elem = types.Unknown;
    if (!types.IsUnknown(coll) && types.Kind(coll) != TypeKind.Collection && !types.IsStruct(coll))
    {
        if (!types.IsArray(coll) && !types.IsString(coll) && !types.IsSlice(coll) && !types.IsFixed(coll))
            CheckError(cg, n.Iterable.Loc, "'foreach' requires an array, a string, a slice, a Fixed<T, N> or a struct with Count() and Get(int), not '" +
                                           types.Name(coll) + "'");
        else
            elem = SliceElemType(cg, coll);
    }
    PushScope(cg);
    int outerDepth = ScopeCount(cg);
    PushScope(cg);
    int varType = elem;
    if (!n.Type.IsNull())
    {
        varType = DeclTypeOf(cg, n.Type);
        if (!types.IsUnknown(elem))
            CheckConversion(cg, Lvalue(elem, "%e", true), varType, s.Loc);
    }
    DeclareVar(cg, n.Name, varType, "%v");
    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = "break", ContinueLabel = "continue", ScopeDepth = outerDepth });
    CheckStmt(cg, n.Body);
    cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);
    PopScope(cg, false);
    PopScope(cg, false);
}

// switch: the subject and every section; the patterns and case values are checked by code generation for now, their
// variables are known here with the unknown type.
void CheckSwitch(Compiler cg, Stmt s)
{
    var n = cg.Tree.GetSwitch(s);
    CheckExpr(cg, n.Subject);
    foreach (var section in n.Sections)
    {
        PushScope(cg);
        foreach (var label in section.Labels)
        {
            if (!label.PatType.IsNull() && label.PatName.Length > 0)
                DeclareVar(cg, label.PatName, cg.Types.Unknown, "%v");
        }
        cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = "break", ContinueLabel = "", ScopeDepth = ScopeCount(cg) });
        foreach (var st in section.Body)
            CheckStmt(cg, st);
        cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);
        PopScope(cg, false);
    }
}
