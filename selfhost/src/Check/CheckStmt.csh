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
    case StmtKind.Expr:
        CheckExpr(cg, cg.Tree.GetExprStmt(s).Expr);
        if (EndsProgram(cg, cg.Tree.GetExprStmt(s).Expr))
            cg.Fn[0].Live = false;
        break;
    case StmtKind.If: CheckIf(cg, s); break;
    case StmtKind.While:
    {
        var n = cg.Tree.GetWhile(s);
        bool reached = cg.Fn[0].Live;
        PushScope(cg); // pattern variables of the condition live for the whole loop
        bool forever = IsLiteralTrue(cg, n.Cond);
        if (!forever)
            CheckCondition(cg, n.Cond);
        var loop = CheckLoopBody(cg, n.Body, true);
        PopScope(cg, false);
        cg.Fn[0].Live = forever ? loop.BreakLabel == "hit" : reached;
        break;
    }
    case StmtKind.DoWhile:
    {
        var n = cg.Tree.GetDoWhile(s);
        var loop = CheckLoopBody(cg, n.Body, true);
        CheckCondition(cg, n.Cond);
        // the condition is reached from the end of the body or a 'continue'; the end from there or a 'break'
        cg.Fn[0].Live = cg.Fn[0].Live || loop.ContinueLabel == "hit" || loop.BreakLabel == "hit";
        break;
    }
    case StmtKind.For:
    {
        var n = cg.Tree.GetFor(s);
        PushScope(cg);
        if (!n.Init.IsNull())
            CheckStmt(cg, n.Init);
        bool reached = cg.Fn[0].Live;
        bool forever = n.Cond.IsNull() || IsLiteralTrue(cg, n.Cond);
        if (!forever)
            CheckCondition(cg, n.Cond);
        var loop = CheckLoopBody(cg, n.Body, true);
        foreach (var it in n.Iterators)
            CheckExpr(cg, it);
        PopScope(cg, false);
        cg.Fn[0].Live = forever ? loop.BreakLabel == "hit" : reached;
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
    case StmtKind.Return:
        CheckReturn(cg, s);
        cg.Fn[0].Live = false;
        break;
    default:
        break;
    }
}

void CheckBlock(Compiler cg, Stmt block, bool newScope)
{
    var b = cg.Tree.GetBlock(block);
    if (b.NoScope)
        newScope = false;
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
// The body of a loop: 'break' and 'continue' are allowed in it. The result tells whether a 'break' / 'continue' was
// reached (BreakLabel / ContinueLabel "hit").
LoopCtx CheckLoopBody(Compiler cg, Stmt body, bool canContinue)
{
    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = "break", ContinueLabel = canContinue ? "continue" : "", ScopeDepth = ScopeCount(cg) });
    CheckStmt(cg, body);
    var loops = cg.Fn[0].Loops;
    var loop = loops.Get(loops.Count() - 1);
    loops.RemoveAt(loops.Count() - 1);
    return loop;
}

// True for a call that does not return (Environment.Exit, Environment.Panic).
bool EndsProgram(Compiler cg, Expr e)
{
    if (e.Kind != ExprKind.Call)
        return false;
    var callee = cg.Tree.GetCall(e).Callee;
    if (callee.Kind != ExprKind.Member)
        return false;
    var m = cg.Tree.GetMember(callee);
    return DottedName(cg, m.Object) == "Environment" && (m.Name == "Exit" || m.Name == "Panic") && !IsLocalName(cg, "Environment");
}

// 'break' / 'continue': the innermost loop (or switch, for 'break') is marked as reached from here, if this statement
// can be reached.
void CheckBreakContinue(Compiler cg, bool isBreak, SourceLoc loc)
{
    var loops = cg.Fn[0].Loops;
    bool live = cg.Fn[0].Live;
    cg.Fn[0].Live = false;
    for (var i = loops.Count() - 1; i >= 0; i -= 1)
    {
        var l = loops.Get(i);
        if (!isBreak && l.ContinueLabel.Length == 0)
            continue;
        if (live)
        {
            if (isBreak)
                l.BreakLabel = "hit";
            else
                l.ContinueLabel = "hit";
            loops.Set(i, l);
        }
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
    if (guard)
        cg.GuardIs = n.Cond.Index;
    else
        PushScope(cg);
    CheckCondition(cg, n.Cond);
    bool reached = cg.Fn[0].Live;
    int bound = cg.Fn[0].Vars.Count() - 1;
    if (guard && bound >= 0)
        SetVarVisible(cg, bound, false);
    CheckBranch(cg, n.Then);
    bool thenLive = cg.Fn[0].Live;
    if (guard && bound >= 0)
        SetVarVisible(cg, bound, true);
    cg.Fn[0].Live = reached;
    if (!n.Else.IsNull())
        CheckBranch(cg, n.Else);
    cg.Fn[0].Live = thenLive || cg.Fn[0].Live;
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
            t = RecoverConstantType(cg, s.Loc, t);
        var sc = ConstScope { File = cg.Fn[0].File, Locals = true, What = "constant '" + d.Name + "'", DeclLoc = s.Loc, Env = cg.Fn[0].Env };
        ConstVal cv = IsEmbedExpr(d.Init) ? ConstEmbed(cg, d.Init, t) : ConstConvert(cg, ConstEvalAs(cg, d.Init, sc, t), t, d.Init.Loc, false);
        DeclareVar(cg, d.Name, t, "");
        var vars = cg.Fn[0].Vars;
        var constVar = vars.Get(vars.Count() - 1);
        constVar.IsConstant = true;
        constVar.ConstValue = cv;
        vars.Set(vars.Count() - 1, constVar);
        NoteDeclared(cg, d.NameLoc, s.Loc, false, d.Type, RefKind.None); // after the value: the hover shows it
        return;
    }
    if (t != 0 && types.IsVoid(t))
    {
        CheckError(cg, s.Loc, "variable '" + d.Name + "' cannot have type 'void'");
        t = types.Unknown;
    }
    Value init = Value { };
    if (!d.Init.IsNull())
        init = t != 0 ? CheckExprAs(cg, d.Init, t) : CheckExpr(cg, d.Init);
    if (t == 0)
    {
        if (d.Init.IsNull())
        {
            CheckError(cg, s.Loc, "cannot infer the type of '" + d.Name + "': 'var' needs an initializer");
            t = types.Unknown;
        }
        else
        {
            init = SettleChecked(cg, init); // var a = [1, 2]: an int[]
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
    NoteDeclared(cg, d.NameLoc, s.Loc, false, d.Type, RefKind.None);
}

// Reports if the value does not convert implicitly to the type (see ConvertValue).
void CheckConversion(Compiler cg, Value v, int to, SourceLoc loc)
{
    var types = cg.Types;
    if (IsUnknown(cg, v) || types.IsUnknown(to))
        return;
    var k = types.Kind(v.Type);
    if (k == TypeKind.Collection)
    {
        CheckCollectionAs(cg, v.CollectionNode, to, loc);
        return;
    }
    // lambdas and function names are converted by code generation for now
    if (k == TypeKind.Lambda || k == TypeKind.MethodGroup || types.IsCFunction(to))
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
    if (types.IsUnknown(rt))
    {
        // in a lambda; the first return gives the result type if it is inferred (LambdaResultType)
        int t = n.Value.IsNull() ? types.Void : CheckRValue(cg, n.Value).Type;
        if (cg.Fn[0].CollectReturns && cg.Fn[0].LambdaReturn == 0)
            cg.Fn[0].LambdaReturn = t;
        return;
    }
    if (!n.Value.IsNull())
    {
        if (types.IsVoid(rt))
        {
            CheckError(cg, s.Loc, "a void function cannot return a value");
            CheckExpr(cg, n.Value);
            return;
        }
        CheckConversion(cg, CheckExprAs(cg, n.Value, rt), rt, n.Value.Loc);
        return;
    }
    if (!types.IsVoid(rt) && !IsVoidResult(cg, rt))
        CheckError(cg, s.Loc, "a return value of type '" + types.Name(rt) + "' is required");
}

// foreach: the loop variable has the element type (see EmitForeach): of an array, a string, a slice, a Fixed or the
// result of Get(int) of a struct with Count() and Get(int).
void CheckForeach(Compiler cg, Stmt s)
{
    var types = cg.Types;
    var n = cg.Tree.GetForeach(s);
    Value it = SettleChecked(cg, CheckRValue(cg, n.Iterable));
    int coll = it.Type;
    int elem = types.Unknown;
    if (types.IsStruct(coll))
        elem = ForeachStructElem(cg, coll, n.Iterable.Loc);
    else if (!types.IsUnknown(coll) && types.Kind(coll) != TypeKind.Collection)
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
    NoteDeclared(cg, n.NameLoc, s.Loc, false, n.Type, RefKind.None);
    bool reached = cg.Fn[0].Live;
    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = "break", ContinueLabel = "continue", ScopeDepth = outerDepth });
    CheckStmt(cg, n.Body);
    cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);
    PopScope(cg, false);
    PopScope(cg, false);
    cg.Fn[0].Live = reached;
}

// switch: the subject, the labels and every section (see EmitSwitch); whether the switch is exhaustive and whether a
// section falls through are checked by code generation for now.
void CheckSwitch(Compiler cg, Stmt s)
{
    var types = cg.Types;
    var n = cg.Tree.GetSwitch(s);
    PushScope(cg);
    Value subj = CheckRValue(cg, n.Subject);
    int st = subj.Type;
    bool known = !types.IsUnknown(st);
    bool hasDefault = false;
    // what the labels cover, for the exhaustiveness check (as in EmitSwitch); allKnown is false if a label could not
    // be followed, and then the check is left to code generation
    var coveredMembers = List<int>.Create();
    var coveredValues = List<string>.Create();
    bool failureCovered = false;
    bool allKnown = known;
    for (var i = 0; i < n.Sections.Length; i += 1)
    {
        foreach (var label in n.Sections[i].Labels)
        {
            if (label.IsDefault)
            {
                if (hasDefault)
                    CheckError(cg, label.Loc, "the switch already has a 'default' label");
                hasDefault = true;
                continue;
            }
            if (!label.PatType.IsNull())
            {
                if (known)
                {
                    CheckPatternLabel(cg, st, label);
                    bool isError = false;
                    string ignored = "";
                    int pt = ResultPatternTypeOrError(cg, st, label.PatType, ref isError, ref ignored);
                    if (pt == 0)
                        allKnown = false;
                    else if (isError || IsErrorEnum(cg, pt))
                        failureCovered = true;
                    else if (IsUnionType(cg, st) && UnionMemberIndex(cg, st, pt) >= 0)
                        coveredMembers.Add(UnionMemberIndex(cg, st, pt));
                    else
                        allKnown = false; // an error in the label: the coverage is not checked
                }
            }
            else if (known && types.IsError(st) && types.Code(st) != 0)
            {
                Value cv = CheckRValue(cg, label.Value);
                CheckConversion(cg, cv, types.Code(st), label.Loc);
                if (cv.Type == types.Code(st) && cv.V.Length > 0)
                    coveredValues.Add(cv.V);
                else
                    allKnown = false;
            }
            else
            {
                Value lv = CheckRValue(cg, label.Value);
                if (types.IsEnum(st))
                {
                    if (lv.Type == st && lv.V.Length > 0)
                        coveredValues.Add(lv.V);
                    else
                        allKnown = false;
                }
                if (known && !IsUnknown(cg, lv))
                {
                    string why = types.IsEnum(st) ? ConversionError(cg, lv, st) : "";
                    if (why.Length == 0 && CompareType(cg, BinOp.Eq, Rvalue(st, "", false), lv, ref why) != 0)
                        why = "";
                    ReportIf(cg, label.Loc, why);
                }
            }
        }
    }
    if (!hasDefault && allKnown)
        ReportIf(cg, s.Loc, ExhaustiveError(cg, st, coveredMembers, coveredValues, failureCovered));
    bool reached = cg.Fn[0].Live;
    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = "break", ContinueLabel = "", ScopeDepth = ScopeCount(cg) });
    foreach (var section in n.Sections)
    {
        cg.Fn[0].Live = reached;
        PushScope(cg);
        foreach (var label in section.Labels)
        {
            if (label.PatType.IsNull() || label.PatName.Length == 0)
                continue;
            int bound = types.Unknown;
            if (known)
            {
                bool isError = false;
                string why = "";
                int pt = ResultPatternTypeOrError(cg, st, label.PatType, ref isError, ref why);
                if (pt != 0)
                    bound = pt;
            }
            DeclareVar(cg, label.PatName, bound, "%v");
            NoteVar(cg, label.Loc, false);
        }
        foreach (var st2 in section.Body)
            CheckStmt(cg, st2);
        if (cg.Fn[0].Live)
            CheckError(cg, section.Loc, "control cannot fall through from one case label to another (missing 'break')");
        PopScope(cg, false);
    }
    var loops = cg.Fn[0].Loops;
    bool broken = loops.Get(loops.Count() - 1).BreakLabel == "hit";
    loops.RemoveAt(loops.Count() - 1);
    PopScope(cg, false);
    cg.Fn[0].Live = reached && (!hasDefault || broken);
}

// 'case T name:' / 'case error e:' on a result or a union (see EmitSwitch).
void CheckPatternLabel(Compiler cg, int st, CaseLabel label)
{
    var types = cg.Types;
    bool isError = false;
    string why = "";
    int pt = ResultPatternTypeOrError(cg, st, label.PatType, ref isError, ref why);
    if (pt == 0)
    {
        CheckError(cg, label.Loc, why);
        return;
    }
    if (isError || IsErrorEnum(cg, pt))
        return;
    if (IsUnionType(cg, st))
    {
        if (UnionMemberIndex(cg, st, pt) < 0)
            CheckError(cg, label.Loc, "'" + types.Name(pt) + "' is not a member of union '" + types.Name(st) + "'");
        return;
    }
    if (!(types.IsResultLike(st) && types.Elem(st) == pt))
        CheckError(cg, label.Loc, "pattern type '" + types.Name(pt) + "' does not match the switch subject of type '" + types.Name(st) + "'");
}

// The element type of 'foreach' over a struct: the result of its Get(int), with an 'int Count()' (see
// EmitForeachStruct); unknown after an error.
int ForeachStructElem(Compiler cg, int coll, SourceLoc loc)
{
    var types = cg.Types;
    string needs = "'foreach' over struct '" + types.Name(coll) + "' needs the methods 'int Count()' and 'T Get(int index)'";
    var countCands = MethodCandidates(cg, coll, "Count");
    var getCands = MethodCandidates(cg, coll, "Get");
    if (countCands.Length == 0 || getCands.Length == 0)
    {
        CheckError(cg, loc, needs);
        return types.Unknown;
    }
    string why = "";
    int countInstance = TryResolveOverload(cg, countCands, new Arg[0], new int[0], loc, "Count", ref why);
    if (ReportIf(cg, loc, why))
        return types.Unknown;
    var probe = new Arg[1];
    probe[0] = Arg { V = ConstInt(cg, types.I32, 0) };
    int getInstance = TryResolveOverload(cg, getCands, probe, new int[0], loc, "Get", ref why);
    if (ReportIf(cg, loc, why))
        return types.Unknown;
    var countFn = cg.Instances.Get(countInstance);
    var getFn = cg.Instances.Get(getInstance);
    if (!countFn.HasThis || !getFn.HasThis || countFn.Ret != types.I32 || types.IsVoid(getFn.Ret) ||
        getFn.ParamTypes[0] != types.I32 || getFn.ParamRefs[0] != 0)
    {
        CheckError(cg, loc, needs);
        return types.Unknown;
    }
    return getFn.Ret;
}
