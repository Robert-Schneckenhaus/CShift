// The checker for expressions: the Value of an expression without its code. Kinds of expressions it does not check yet
// have the unknown type (their parts are still checked); code generation checks them.

namespace CShift.Check;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.CodeGen;

Value CheckRValue(Compiler cg, Expr e)
{
    Value v = CheckExpr(cg, e);
    v.IsLValue = false;
    v.IsConst = false;
    v.IsRefArg = false;
    return v;
}

Value CheckExpr(Compiler cg, Expr e)
{
    var tree = cg.Tree;
    switch (e.Kind)
    {
    case ExprKind.IntLit:
    case ExprKind.FloatLit:
    case ExprKind.CharLit:
    case ExprKind.StringLit:
    case ExprKind.BoolLit:
    case ExprKind.NullLit:
        return EmitLiteral(cg, e);
    case ExprKind.Name: return CheckName(cg, e);
    case ExprKind.Member: return CheckMember(cg, e);
    case ExprKind.Call: return CheckCall(cg, e, false);
    case ExprKind.Start:
    {
        var s = tree.GetStart(e);
        if (s.Operand.Kind != ExprKind.Call)
        {
            CheckError(cg, e.Loc, "'start' must be followed directly by a call, e.g. 'start Foo(...)'");
            CheckExpr(cg, s.Operand);
            return UnknownValue(cg);
        }
        if (cg.Ir.Target.Wasm)
            CheckError(cg, e.Loc, "'start' is not available on WebAssembly: a WebAssembly program has only one thread");
        return CheckCall(cg, s.Operand, true);
    }
    case ExprKind.Index: return CheckIndex(cg, e);
    case ExprKind.Slice: return CheckSliceExpr(cg, e);
    case ExprKind.NewArray: return CheckNewArray(cg, e);
    case ExprKind.NewObject: return CheckNewObject(cg, e);
    case ExprKind.StructInit: return CheckStructInit(cg, e);
    case ExprKind.Unary: return CheckUnary(cg, e);
    case ExprKind.Binary: return CheckBinary(cg, e);
    case ExprKind.Assign: return CheckAssign(cg, e);
    case ExprKind.Conditional: return CheckConditionalIn(cg, e, 0);
    case ExprKind.Cast: return CheckCast(cg, e);
    case ExprKind.Try: return CheckTry(cg, e);
    case ExprKind.ErrorLit: return CheckErrorLit(cg, e);
    case ExprKind.This:
        if (cg.Fn[0].ThisSlot.Length == 0)
        {
            CheckError(cg, e.Loc, "'this' is not available in a static context");
            return UnknownValue(cg);
        }
        return Lvalue(CurrentOwner(cg), "%this", false);
    case ExprKind.Unchecked:
        return CheckExpr(cg, tree.GetUnchecked(e).Operand);
    case ExprKind.RefArg:
    {
        Value o = CheckExpr(cg, tree.GetRefArg(e).Operand);
        if (IsUnknown(cg, o))
            return o;
        if (!o.IsLValue)
        {
            CheckError(cg, e.Loc, "'ref' can only be applied to a variable, field or element");
            return UnknownValue(cg);
        }
        o.IsRefArg = true;
        return o;
    }
    case ExprKind.Is: return CheckIs(cg, e);
    case ExprKind.Collection: return CheckCollectionExpr(cg, e);
    case ExprKind.Lambda:
        CheckLambdaBody(cg, e, new int[0]);
        return UnknownValue(cg); // its type comes from the Action/Func it is converted to (code generation for now)
    case ExprKind.Embed:
    case ExprKind.EmbedFilenames:
        CheckError(cg, e.Loc, EmbedPlaceError());
        return UnknownValue(cg);
    default:
        CheckParts(cg, e);
        return UnknownValue(cg);
    }
}

// The parts of an expression that the checker does not type yet, so that the errors inside them are found.
void CheckParts(Compiler cg, Expr e)
{
    switch (e.Kind)
    {
    default:
        break; // sizeof, default(T), new T(): later steps
    }
}

// A name as a value (see EmitName).
Value CheckName(Compiler cg, Expr e)
{
    var n = cg.Tree.GetName(e);
    Value v = LookupVariable(cg, n.Name);
    if (!v.IsNone())
    {
        IndexLocal(cg, e.Loc, n.Name);
        if (IsInterfaceType(cg, v.Type) && IsCapturedName(cg, n.Name))
            CheckError(cg, e.Loc, "a lambda cannot use the interface parameter '" + n.Name + "' (the lambda could outlive the " +
                                  "struct it points to)");
        return v;
    }
    int owner = CurrentOwner(cg);
    if (owner != 0 && FindField(cg, owner, n.Name).Found)
    {
        IndexField(cg, e.Loc, owner, n.Name);
        if (cg.Fn[0].ThisSlot.Length == 0)
        {
            CheckError(cg, e.Loc, "'this' is not available in a static context");
            return UnknownValue(cg);
        }
        return CheckField(cg, Lvalue(owner, "%this", false), n.Name, e.Loc);
    }
    int c = LookupConst(cg, cg.Fn[0].File, n.Name);
    if (c >= 0)
    {
        IndexConst(cg, e.Loc, n.Name.Length, c);
        return EmitConst(cg, c, e.Loc);
    }
    int g = LookupGlobal(cg, cg.Fn[0].File, n.Name);
    if (g >= 0)
    {
        IndexGlobal(cg, e.Loc, n.Name.Length, g);
        return GlobalUse(cg, g);
    }
    // a function name as a value: it converts to a matching Action/Func type (see CheckConversion)
    var group = new Candidate[0];
    if (owner != 0)
        group = MethodCandidates(cg, owner, n.Name);
    if (group.Length == 0)
        group = FreeCandidates(cg, cg.Fn[0].File, n.Name);
    if (group.Length > 0)
        return n.TypeArgs.Length > 0 ? UnknownValue(cg) : GroupValue(cg, group, new int[0], n.Name);
    if (!cg.St[0].StdlibLoaded && IsStdlibName(n.Name))
        CheckError(cg, e.Loc, "cshc does not support the standard library yet ('" + n.Name + "')");
    else if (FindLocal(cg, n.Name + " (not assigned here)") >= 0)
        CheckError(cg, e.Loc, "'" + n.Name + "' is not assigned here: 'x is not T " + n.Name + "' assigns it only where the pattern " +
                              "matched (the 'else' branch, or after the 'if' when its branch returns, breaks or continues)");
    else
        CheckError(cg, e.Loc, "undefined name '" + n.Name + "'");
    return UnknownValue(cg);
}

// A field of a struct value (see FieldAccess): an lvalue if the object is one.
Value CheckField(Compiler cg, Value obj, string name, SourceLoc loc)
{
    var p = FindField(cg, obj.Type, name);
    if (!p.Found)
    {
        CheckError(cg, loc, "struct '" + cg.Types.Name(obj.Type) + "' has no field '" + name + "'");
        return UnknownValue(cg);
    }
    if (p.IsPrivate && CurrentOwner(cg) != p.Owner)
    {
        CheckError(cg, loc, "field '" + name + "' is private to '" + cg.Types.Name(p.Owner) + "'");
        return UnknownValue(cg);
    }
    if (obj.IsLValue)
        return Lvalue(p.Type, "%f", obj.IsConst);
    return Rvalue(p.Type, "", false);
}

Arg[] CheckArgs(Compiler cg, Expr[] args, ref bool known)
{
    var list = new Arg[args.Length];
    for (var i = 0; i < args.Length; i += 1)
    {
        list[i] = Arg { Source = args[i], V = CheckExpr(cg, args[i]) };
        if (IsUnknown(cg, list[i].V))
            known = false;
    }
    return list;
}

// The arguments of a call to one of the candidates: integer arithmetic in an argument is computed in the type of the
// parameter when the candidates agree on it (see ArgFrames and EmitArgsFor).
Arg[] CheckArgsFor(Compiler cg, Expr[] args, Candidate[] cands, ref bool known)
{
    int[] frames = ArgFrames(cg, cands, args.Length);
    int[] targets = ArgTargets(cg, cands, args.Length);
    var list = new Arg[args.Length];
    for (var i = 0; i < args.Length; i += 1)
    {
        if (IsTypelessNew(cg, args[i]))
            list[i] = Arg { Source = args[i], V = CheckTypelessNew(cg, args[i], targets[i]) };
        else
            list[i] = Arg { Source = args[i], V = frames[i] != 0 ? CheckExprAs(cg, args[i], frames[i]) : CheckExpr(cg, args[i]) };
        if (IsUnknown(cg, list[i].V))
            known = false;
    }
    return list;
}

// Calls by name and methods of struct values (see EmitCallVia, EmitNameCall, EmitMemberCall).
Value CheckCall(Compiler cg, Expr e, bool viaStart)
{
    var call = cg.Tree.GetCall(e);
    bool known = true;
    // the errors of a call (no such function, no matching overload, ...) point at the function's name; the node itself
    // has the place of '('
    if (call.Callee.Kind == ExprKind.Name)
    {
        e.Loc = call.Callee.Loc;
        return CheckNameCall(cg, e, call, cg.Tree.GetName(call.Callee), viaStart);
    }
    if (call.Callee.Kind == ExprKind.Member)
    {
        var m = cg.Tree.GetMember(call.Callee);
        if (m.NameLoc.Line > 0)
            e.Loc = m.NameLoc;
        return CheckMemberCall(cg, e, call, m, viaStart);
    }
    CheckExpr(cg, call.Callee);
    CheckArgs(cg, call.Args, ref known);
    return UnknownValue(cg);
}

// A call through a function value (see EmitIndirectCall): the number of arguments and their conversions.
Value CheckIndirectCall(Compiler cg, int ft, Expr[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ptypes = types.Params(ft);
    if (args.Length != ptypes.Length)
    {
        CheckError(cg, loc, "a call of '" + types.Name(ft) + "' needs " + ptypes.Length.ToString() + " argument(s), got " +
                            args.Length.ToString());
        foreach (var a in args)
            CheckExpr(cg, a);
        return UnknownValue(cg);
    }
    for (var i = 0; i < args.Length; i += 1)
    {
        Value v = CheckExprAs(cg, args[i], ptypes[i]);
        if (v.IsRefArg)
            CheckError(cg, args[i].Loc, "function values (Action/Func) have no 'ref' parameters");
        else
            CheckConversion(cg, v, ptypes[i], cg.Tree.StartOf(args[i]));
    }
    return Rvalue(types.Elem(ft), "", false);
}

Value CheckNameCall(Compiler cg, Expr e, CallExpr call, NameExpr n, bool viaStart)
{
    bool known = true;
    Value variable = LookupVariable(cg, n.Name);
    if (!variable.IsNone())
    {
        if (!IsUnknown(cg, variable) && !IsCallableType(cg, variable.Type))
            CheckError(cg, e.Loc, "'" + n.Name + "' is a variable, not a function");
        if (!IsUnknown(cg, variable) && cg.Types.IsFunction(variable.Type))
            return CheckIndirectCall(cg, variable.Type, call.Args, e.Loc);
        CheckArgs(cg, call.Args, ref known);
        return UnknownValue(cg);
    }
    int owner = CurrentOwner(cg);
    if (owner != 0)
    {
        var fieldPath = FindField(cg, owner, n.Name);
        if (fieldPath.Found && IsCallableType(cg, fieldPath.Type))
        {
            IndexField(cg, call.Callee.Loc, owner, n.Name);
            CheckArgs(cg, call.Args, ref known);
            return UnknownValue(cg);
        }
    }
    int g = LookupGlobal(cg, cg.Fn[0].File, n.Name);
    if (g >= 0 && (owner == 0 || MethodCandidates(cg, owner, n.Name).Length == 0) && IsCallableType(cg, GlobalUse(cg, g).Type))
    {
        CheckArgs(cg, call.Args, ref known);
        return UnknownValue(cg);
    }
    var cands = new Candidate[0];
    if (owner != 0)
        cands = MethodCandidates(cg, owner, n.Name);
    if (cands.Length == 0)
        cands = FreeCandidates(cg, cg.Fn[0].File, n.Name);
    var args = CheckArgsFor(cg, call.Args, cands, ref known);
    if (cands.Length == 0)
    {
        CheckError(cg, e.Loc, "undefined function '" + n.Name + "'");
        return UnknownValue(cg);
    }
    if (!known)
    {
        IndexCandidates(cg, call.Callee.Loc, n.Name.Length, cands);
        return UnknownValue(cg);
    }
    string why = "";
    int instance = CheckOverload(cg, cands, args, ResolveTypeArgs(cg, n.TypeArgs), e.Loc, n.Name, ref why);
    if (instance < 0)
    {
        IndexCandidates(cg, call.Callee.Loc, n.Name.Length, cands);
        ReportIf(cg, e.Loc, why);
        return UnknownValue(cg);
    }
    IndexFunction(cg, call.Callee.Loc, n.Name.Length, instance);
    if (IsThreadInstance(cg, instance))
    {
        if (!viaStart)
            CheckError(cg, e.Loc, "call to the 'thread' function '" + n.Name + "' must be prefixed with 'start': 'start " + n.Name + "(...)'");
        return UnknownValue(cg);
    }
    if (viaStart)
    {
        CheckError(cg, e.Loc, "'start' can only be used with a 'thread' function, not '" + n.Name + "'");
        return UnknownValue(cg);
    }
    var fi = cg.Instances.Get(instance);
    if (fi.HasThis && cg.Fn[0].ThisSlot.Length == 0)
    {
        CheckError(cg, e.Loc, "cannot call the instance method '" + n.Name + "' from a static context");
        return UnknownValue(cg);
    }
    return Rvalue(fi.Ret, "", false);
}

Value CheckUnary(Compiler cg, Expr e)
{
    var u = cg.Tree.GetUnary(e);
    if (u.Op == UnOp.Deref)
    {
        bool unsafeError = ReportIf(cg, e.Loc, UnsafeError(cg, "pointer dereference"));
        Value p = CheckRValue(cg, u.Operand);
        if (unsafeError || cg.Types.IsUnknown(p.Type) || ReportIf(cg, e.Loc, DerefError(cg, p.Type)))
            return UnknownValue(cg);
        return Lvalue(cg.Types.Elem(p.Type), "", false);
    }
    if (u.Op == UnOp.AddrOf)
    {
        bool unsafeError = ReportIf(cg, e.Loc, UnsafeError(cg, "taking an address"));
        Value o = CheckExpr(cg, u.Operand);
        if (unsafeError || cg.Types.IsUnknown(o.Type))
            return UnknownValue(cg);
        return Rvalue(cg.Types.PointerTo(o.Type), "", false);
    }
    Value v = CheckRValue(cg, u.Operand);
    string why = "";
    Value r = UnaryResult(cg, u.Op, v, ref why);
    if (r.Type == 0)
    {
        CheckError(cg, e.Loc, why);
        return UnknownValue(cg);
    }
    return r;
}

// a op b. Like code generation, a left-deep chain (a + b + c ...) is walked in a loop, not by recursion.
Value CheckBinary(Compiler cg, Expr e)
{
    var types = cg.Types;
    var b = cg.Tree.GetBinary(e);
    if (b.Op == BinOp.LogAnd || b.Op == BinOp.LogOr)
    {
        Expr leftmost = e;
        var rights = List<Expr>.Create();
        while (leftmost.Kind == ExprKind.Binary && cg.Tree.GetBinary(leftmost).Op == b.Op)
        {
            rights.Add(cg.Tree.GetBinary(leftmost).Rhs);
            leftmost = cg.Tree.GetBinary(leftmost).Lhs;
        }
        CheckCondition(cg, leftmost);
        for (var i = rights.Count() - 1; i >= 0; i -= 1)
            CheckCondition(cg, rights.Get(i));
        return Rvalue(types.Bool, "", false);
    }
    var chain = List<Expr>.Create();
    Expr first = e;
    while (first.Kind == ExprKind.Binary)
    {
        var lb = cg.Tree.GetBinary(first);
        if (lb.Op == BinOp.LogAnd || lb.Op == BinOp.LogOr)
            break;
        chain.Add(first);
        first = lb.Lhs;
    }
    Value l = CheckRValue(cg, first);
    for (var i = chain.Count() - 1; i >= 0; i -= 1)
    {
        Expr step = chain.Get(i);
        var sb = cg.Tree.GetBinary(step);
        Value r = CheckRValue(cg, sb.Rhs);
        string why = "";
        bool compare = sb.Op == BinOp.Eq || sb.Op == BinOp.Ne || sb.Op == BinOp.Lt || sb.Op == BinOp.Gt || sb.Op == BinOp.Le || sb.Op == BinOp.Ge;
        int t = compare ? CompareType(cg, sb.Op, l, r, ref why) : ArithmeticType(cg, sb.Op, l, r, ref why);
        if (t == 0)
        {
            CheckError(cg, step.Loc, why);
            t = types.Unknown;
        }
        l = Rvalue(t, "", false);
    }
    return l;
}

// ---------------------------------------------------------------------------
// Target-typed integer arithmetic (see ArithmeticFrame in CodeGen/Rules.csh and EmitExprAs)
// ---------------------------------------------------------------------------

// An expression used as a value of 'target'.
Value CheckExprAs(Compiler cg, Expr e, int target)
{
    if (IsTypelessNew(cg, e))
        return CheckTypelessNew(cg, e, target);
    if (e.Kind == ExprKind.Lambda && cg.Types.IsFunction(target))
    {
        // a lambda converted to an Action/Func: its parameters must fit, its body gets their types
        SourceLoc where = e.Loc;
        string wrong = LambdaSignatureError(cg, e, target, ref where);
        if (wrong.Length > 0)
        {
            CheckError(cg, where, wrong);
            CheckLambdaBody(cg, e, new int[0]);
            return UnknownValue(cg);
        }
        CheckLambdaBody(cg, e, cg.Types.Params(target));
        return Rvalue(target, "", false);
    }
    int frame = ArithmeticFrame(cg, target);
    if (frame == 0 || !IsFramable(cg, e))
        return CheckExpr(cg, e);
    return CheckFramed(cg, e, frame);
}

// cond ? a : b; with a frame the branches are computed in it (see EmitConditionalIn).
Value CheckConditionalIn(Compiler cg, Expr e, int frame)
{
    var c = cg.Tree.GetCond(e);
    CheckCondition(cg, c.Cond);
    Value a = frame != 0 ? CheckFramed(cg, c.Then, frame) : CheckRValue(cg, c.Then);
    Value b = frame != 0 ? CheckFramed(cg, c.Else, frame) : CheckRValue(cg, c.Else);
    string why = "";
    int t = ConditionalType(cg, a, b, ref why);
    if (t == 0)
    {
        CheckError(cg, e.Loc, why);
        return UnknownValue(cg);
    }
    return Rvalue(t, "", false);
}

// An operand of a framed expression (see EmitFramed).
Value CheckFramed(Compiler cg, Expr e, int frame)
{
    if (!IsFramable(cg, e))
        return CheckRValue(cg, e);
    if (e.Kind == ExprKind.Conditional)
        return CheckConditionalIn(cg, e, frame);
    if (e.Kind == ExprKind.Unchecked)
        return CheckFramed(cg, cg.Tree.GetUnchecked(e).Operand, frame);
    if (e.Kind == ExprKind.Unary)
    {
        var u = cg.Tree.GetUnary(e);
        Value operand = CheckFramed(cg, u.Operand, frame);
        if (u.Op == UnOp.Neg && operand.HasLit)
            return NegateLiteral(cg, operand);
        if (FramedUnaryType(cg, u.Op, operand, frame) == frame)
            return Rvalue(frame, "", false);
        string why = "";
        Value r = UnaryResult(cg, u.Op, operand, ref why);
        if (r.Type == 0)
        {
            CheckError(cg, e.Loc, why);
            return UnknownValue(cg);
        }
        return r;
    }
    var chain = List<Expr>.Create();
    Expr leftmost = e;
    while (leftmost.Kind == ExprKind.Binary && IsFramable(cg, leftmost))
    {
        chain.Add(leftmost);
        leftmost = cg.Tree.GetBinary(leftmost).Lhs;
    }
    Value l = CheckFramed(cg, leftmost, frame);
    for (var i = chain.Count() - 1; i >= 0; i -= 1)
    {
        Expr step = chain.Get(i);
        var sb = cg.Tree.GetBinary(step);
        Value r = sb.Op == BinOp.Shl || sb.Op == BinOp.Shr ? CheckRValue(cg, sb.Rhs) : CheckFramed(cg, sb.Rhs, frame);
        l = CheckFramedStep(cg, sb.Op, l, r, frame, step.Loc);
    }
    return l;
}

// l op r in the frame if both fit, otherwise by the usual rules (see EmitFramedStep).
Value CheckFramedStep(Compiler cg, BinOp op, Value l, Value r, int frame, SourceLoc loc)
{
    bool folded = false;
    Value lit = FoldLiterals(cg, op, l, r, ref folded);
    if (folded)
        return lit;
    if (FramedArithmeticType(cg, op, l, r, frame) == frame)
        return Rvalue(frame, "", false);
    string why = "";
    int t = ArithmeticType(cg, op, l, r, ref why);
    if (t == 0)
    {
        CheckError(cg, loc, why);
        return UnknownValue(cg);
    }
    return Rvalue(t, "", false);
}

// target = value, target op= value (see EmitAssign). Elements of arrays, slices and Fixed values are checked; indexers
// (x[k] = v on a struct) and string elements are left to code generation for now.
Value CheckAssign(Compiler cg, Expr e)
{
    var types = cg.Types;
    var a = cg.Tree.GetAssign(e);
    Value target;
    if (a.Target.Kind == ExprKind.Index)
    {
        var ix = cg.Tree.GetIndex(a.Target);
        Value holder = CheckExpr(cg, ix.Object);
        CheckExpr(cg, ix.Index);
        int ht = holder.Type;
        if (!(types.IsArray(ht) || types.Kind(ht) == TypeKind.Slice || types.IsFixed(ht)))
        {
            if (types.IsStringSlice(ht))
                CheckError(cg, a.Target.Loc, "a StringSlice is read-only (strings are immutable)");
            else if (types.IsReadOnlySlice(ht))
                CheckError(cg, a.Target.Loc, "a ReadOnlySlice is read-only (use an array or a Slice<T> to change elements)");
            CheckExpr(cg, a.Value);
            return UnknownValue(cg);
        }
        if (types.IsFixed(ht))
            ReportIf(cg, ix.Index.Loc, FixedIndexError(cg, ht, ix.Index, ix.FromEnd));
        target = Lvalue(SliceElemType(cg, ht), "%e", types.IsFixed(ht) && holder.IsConst);
    }
    else
        target = CheckExpr(cg, a.Target);
    if (IsUnknown(cg, target))
    {
        CheckExpr(cg, a.Value);
        return target;
    }
    if (a.Target.Kind == ExprKind.Name && IsCapturedName(cg, cg.Tree.GetName(a.Target).Name))
    {
        CheckError(cg, e.Loc, "cannot assign to '" + cg.Tree.GetName(a.Target).Name + "': a lambda gets a read-only copy of " +
                              "the variables it uses (return the new value instead)");
        CheckExpr(cg, a.Value);
        return UnknownValue(cg);
    }
    if (!target.IsLValue)
    {
        string message = "the left side of an assignment must be a variable, field or element";
        if (a.Target.Kind == ExprKind.Name)
        {
            string constName = cg.Tree.GetName(a.Target).Name;
            int local = FindLocal(cg, constName);
            bool isConstantName = local >= 0 ? cg.Fn[0].Vars.Get(local).IsConstant : LookupConst(cg, cg.Fn[0].File, constName) >= 0;
            if (isConstantName)
                message = "cannot assign to a read-only value: '" + constName + "' is a constant";
        }
        CheckError(cg, e.Loc, message);
        CheckExpr(cg, a.Value);
        return UnknownValue(cg);
    }
    if (target.IsConst)
    {
        if (a.Target.Kind == ExprKind.Name && FindLocal(cg, cg.Tree.GetName(a.Target).Name) < 0 &&
            IsOuterName(cg, cg.Tree.GetName(a.Target).Name))
            CheckError(cg, e.Loc, "cannot assign to '" + cg.Tree.GetName(a.Target).Name + "': a lambda gets a read-only copy of " +
                                  "the variables it uses (return the new value instead)");
        else
            CheckError(cg, e.Loc, "cannot assign to a read-only value (a constant or a 'const ref' parameter)");
        CheckExpr(cg, a.Value);
        return UnknownValue(cg);
    }
    if (a.HasOp)
    {
        // see EmitCompound
        Value cur = target;
        cur.IsLValue = false;
        cur.IsConst = false;
        int frame = ArithmeticFrame(cg, target.Type);
        Value res;
        if (frame != 0 && types.IsIntegral(target.Type))
            res = CheckFramedStep(cg, a.Op, cur, CheckFramed(cg, a.Value, frame), frame, e.Loc);
        else
        {
            Value rhs = CheckRValue(cg, a.Value);
            string why = "";
            int rt = ArithmeticType(cg, a.Op, cur, rhs, ref why);
            if (rt == 0)
                CheckError(cg, e.Loc, why);
            res = rt == 0 ? UnknownValue(cg) : Rvalue(rt, "", false);
        }
        if (!IsUnknown(cg, res) && res.Type != target.Type && !(types.IsNumeric(res.Type) && types.IsNumeric(target.Type)))
            CheckConversion(cg, res, target.Type, e.Loc);
    }
    else
    {
        Value rhs = CheckExprAs(cg, a.Value, target.Type);
        rhs.IsLValue = false;
        rhs.IsConst = false;
        rhs.IsRefArg = false;
        CheckConversion(cg, rhs, target.Type, cg.Tree.StartOf(a.Value));
    }
    return Lvalue(target.Type, target.V, false);
}

// (T)x: the same value if it converts implicitly, numbers into each other; pointer casts are checked by code generation
// for now (see EmitCast).
Value CheckCast(Compiler cg, Expr e)
{
    var types = cg.Types;
    var c = cg.Tree.GetCast(e);
    int to = DeclTypeOf(cg, c.Type);
    Value v = CheckRValue(cg, c.Operand);
    int from = v.Type;
    if (from == to)
        return v;
    if (types.IsUnknown(from) || types.IsUnknown(to) || types.IsPointer(from) || types.IsPointer(to) || ConversionCost(cg, v, to) >= 0)
        return Rvalue(to, "", false);
    bool fromNumeric = types.IsInt(from) || types.IsChar(from) || types.IsEnum(from) || types.IsFloat(from);
    bool toNumeric = types.IsInt(to) || types.IsChar(to) || types.IsEnum(to) || types.IsFloat(to);
    if (fromNumeric && toNumeric)
    {
        if (types.IsEnum(from) && types.IsFloat(to))
            CheckError(cg, e.Loc, "cannot cast an enum to a floating point type");
        return Rvalue(to, "", false);
    }
    CheckError(cg, e.Loc, "cannot cast '" + types.Name(from) + "' to '" + types.Name(to) + "'");
    return Rvalue(to, "", false);
}

// 'try x' (see EmitTry).
Value CheckTry(Compiler cg, Expr e)
{
    var types = cg.Types;
    Value subj = CheckRValue(cg, cg.Tree.GetTry(e).Operand);
    if (IsUnknown(cg, subj))
        return subj;
    if (!types.IsError(subj.Type))
    {
        CheckError(cg, e.Loc, "'try' can only be used with Error<T> values, not '" + types.Name(subj.Type) + "'");
        return UnknownValue(cg);
    }
    int retType = cg.Fn[0].RetType;
    if (types.IsUnknown(retType))
        return Rvalue(types.Elem(subj.Type), "", false); // in a lambda
    bool intMain = cg.St[0].MainFunc == cg.Fn[0].Func + 1 && types.IsInt(retType) || IsMainCandidate(cg);
    if (!types.IsError(retType) && !intMain)
        CheckError(cg, e.Loc, "'try' can only be used in a function that returns Error<T>");
    else if (types.IsError(retType) && types.Code(retType) != 0 && types.Code(retType) != types.Code(subj.Type))
        CheckError(cg, e.Loc, "'try' cannot pass on the error of '" + types.Name(subj.Type) + "' from a function that returns '" +
                              types.Name(retType) + "': its codes are not values of " + types.Name(types.Code(retType)) +
                              "; translate it: 'if (x is error e) return error(e.Message, " + types.Name(types.Code(retType)) + ".Member);'");
    return Rvalue(types.Elem(subj.Type), "", false);
}

// True while the checker is in the function that will be the entry point 'int Main()' (code generation knows it as
// MainFunc; the checker runs before it is chosen).
bool IsMainCandidate(Compiler cg)
{
    var fi = cg.Instances.Get(cg.Fn[0].Func);
    var d = cg.Funcs.Get(fi.Entry).Decl;
    return d.Name == "Main" && fi.Owner == 0 && cg.Types.IsInt(fi.Ret) && !cg.Files.Get(fi.File).IsPrelude;
}

// error("message"), error("message", code), error(E.Member) (see EmitErrorLit).
Value CheckErrorLit(Compiler cg, Expr e)
{
    var types = cg.Types;
    var n = cg.Tree.GetErrorLit(e);
    Value first = CheckRValue(cg, n.Message);
    int codeType = 0;
    if (n.Code.IsNull() && IsErrorEnum(cg, first.Type))
        codeType = first.Type;
    else
    {
        CheckConversion(cg, first, types.String, cg.Tree.StartOf(n.Message));
        if (!n.Code.IsNull())
        {
            Value c = CheckRValue(cg, n.Code);
            if (IsErrorEnum(cg, c.Type))
                codeType = c.Type;
            else
            {
                codeType = -1;
                CheckConversion(cg, c, types.I32, cg.Tree.StartOf(n.Code));
            }
        }
    }
    return Rvalue(types.ErrorLitOf(codeType), "", false);
}

// 'x is P' / 'x is P v' / 'x is not P' on Error<T> and Optional<T> (see EmitIs, EmitIsPattern); interfaces, unions and
// threads are checked by code generation for now. The binding is declared where code generation declares it.
Value CheckIs(Compiler cg, Expr e)
{
    var types = cg.Types;
    var n = cg.Tree.GetIs(e);
    Value boolean = Rvalue(types.Bool, "", false);
    if (n.Negated && n.BindName.Length > 0 && cg.GuardIs != e.Index)
        CheckError(cg, e.Loc, "'is not' can only bind '" + n.BindName + "' as the whole condition of an 'if' (then '" + n.BindName +
                              "' is usable in the 'else' branch, and after the 'if' if its branch returns, breaks or continues)");
    cg.GuardIs = -1;
    Value subj = CheckRValue(cg, n.Operand);
    int bound = types.Unknown;
    int t = subj.Type;
    if (!types.IsUnknown(t) && types.Kind(t) != TypeKind.Interface && !IsUnionType(cg, t))
    {
        if (!types.IsResultLike(t))
        {
            var sd = types.IsStruct(t) ? cg.Structs.Get(GetStructInfo(cg, t).Entry).Decl : StructDecl { };
            if (!(types.IsStruct(t) && sd.Name == "Thread" && sd.TypeParams.Length > 0))
            {
                string shown = types.IsStruct(t) && sd.Name == "_ThreadVoid" ? "Thread" : types.Name(t);
                CheckError(cg, e.Loc, "'is' can only be used with Error<T>, Optional<T> and Thread<T> values, not '" + shown + "'");
            }
        }
        else
        {
            bool isErrorPattern = false;
            string why = "";
            int pattern = ResultPatternTypeOrError(cg, t, n.Type, ref isErrorPattern, ref why);
            var patternLoc = cg.Tree.GetType(n.Type).Loc;
            if (pattern == 0)
                CheckError(cg, patternLoc, why);
            else if (IsErrorEnum(cg, pattern))
                bound = pattern;
            else
            {
                int subject = t;
                if (types.IsError(t) && types.IsOptional(types.Elem(t)) && pattern == types.Elem(types.Elem(t)))
                    subject = types.Elem(t);
                if (pattern != subject && pattern != types.Elem(subject))
                    CheckError(cg, patternLoc, "pattern type '" + types.Name(pattern) + "' does not match the payload type '" +
                                               types.Name(types.Elem(subject)) + "' of '" + types.Name(subject) + "'");
                else
                    bound = pattern;
            }
        }
    }
    else if (!types.IsUnknown(t) && IsUnionType(cg, t) && !n.Type.IsNull())
    {
        // 'u is M m': M must be one of the union's members
        int pattern = DeclTypeOf(cg, n.Type);
        if (!types.IsUnknown(pattern))
        {
            if (UnionMemberIndex(cg, t, pattern) < 0)
                CheckError(cg, cg.Tree.GetType(n.Type).Loc, "'" + types.Name(pattern) + "' is not a member of union '" +
                                                            types.Name(t) + "'");
            else
                bound = pattern;
        }
    }
    if (n.BindName.Length > 0)
    {
        CheckNotDeclared(cg, e.Loc, n.BindName);
        DeclareVar(cg, n.BindName, bound, "%v");
        NoteVar(cg, e.Loc, false);
    }
    return boolean;
}

// The body of a lambda, in a scope of its own: its parameters (with the unknown type unless they are written), and the
// variables of the enclosing function, which a lambda reads. Its 'return' belongs to the lambda, whose result type is
// not known here, and 'break'/'continue' cannot leave it.
void CheckLambdaBody(Compiler cg, Expr e, int[] paramTypes)
{
    var l = cg.Tree.GetLambda(e);
    int savedRet = cg.Fn[0].RetType;
    int savedLambdaVars = cg.Fn[0].LambdaVars;
    cg.Fn[0].LambdaVars = cg.Fn[0].Vars.Count() + 1;
    var savedLoops = cg.Fn[0].Loops;
    bool savedLive = cg.Fn[0].Live;
    bool savedCollect = cg.Fn[0].CollectReturns;
    cg.Fn[0].Live = true;
    cg.Fn[0].CollectReturns = false; // its returns are its own
    cg.Fn[0].RetType = cg.Types.Unknown;
    cg.Fn[0].Loops = List<LoopCtx>.Create();
    PushScope(cg);
    for (var i = 0; i < l.Params.Length; i += 1)
    {
        var p = l.Params[i];
        int pt = !p.Type.IsNull() ? DeclTypeOf(cg, p.Type) : i < paramTypes.Length ? paramTypes[i] : cg.Types.Unknown;
        CheckNotDeclared(cg, p.NameLoc.Line > 0 ? p.NameLoc : p.Loc, p.Name);
        DeclareVar(cg, p.Name, pt, "%p");
        NoteDeclared(cg, p.NameLoc, p.Loc, true, p.Type, p.Ref);
        NoteTypeParamVar(cg, p.Name, p.Type);
    }
    if (!l.Block.IsNull())
        CheckBlock(cg, l.Block, true);
    else
        CheckExpr(cg, l.Body);
    PopScope(cg, false);
    cg.Fn[0].RetType = savedRet;
    cg.Fn[0].Loops = savedLoops;
    cg.Fn[0].Live = savedLive;
    cg.Fn[0].CollectReturns = savedCollect;
    cg.Fn[0].LambdaVars = savedLambdaVars;
}

// True if the local variable 'name' belongs to a function or lambda around the lambda whose body is checked.
bool IsCapturedName(Compiler cg, string name)
{
    int start = cg.Fn[0].LambdaVars - 1;
    if (start < 0)
        return false;
    int local = FindLocal(cg, name);
    return local >= 0 && local < start;
}
