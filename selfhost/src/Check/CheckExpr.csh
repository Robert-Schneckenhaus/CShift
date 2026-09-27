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
    case ExprKind.Conditional:
    {
        var c = tree.GetCond(e);
        CheckCondition(cg, c.Cond);
        Value a = CheckRValue(cg, c.Then);
        Value b = CheckRValue(cg, c.Else);
        string why = "";
        int t = ConditionalType(cg, a, b, ref why);
        if (t == 0)
        {
            CheckError(cg, e.Loc, why);
            return UnknownValue(cg);
        }
        return Rvalue(t, "", false);
    }
    case ExprKind.Cast:
    {
        var c = tree.GetCast(e);
        int to = DeclTypeOf(cg, c.Type);
        CheckExpr(cg, c.Operand);
        return Rvalue(to, "", false); // whether the cast is allowed is checked by code generation for now
    }
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
    case ExprKind.Is:
    {
        var n = tree.GetIs(e);
        CheckExpr(cg, n.Operand);
        if (n.BindName.Length > 0)
            DeclareVar(cg, n.BindName, cg.Types.Unknown, "%v"); // the pattern is checked by code generation for now
        return Rvalue(cg.Types.Bool, "", false);
    }
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
    var tree = cg.Tree;
    switch (e.Kind)
    {
    case ExprKind.Try:
        CheckExpr(cg, tree.GetTry(e).Operand);
        break;
    case ExprKind.ErrorLit:
    {
        var n = tree.GetErrorLit(e);
        CheckExpr(cg, n.Message);
        if (!n.Code.IsNull())
            CheckExpr(cg, n.Code);
        break;
    }
    case ExprKind.Collection:
        foreach (var item in tree.GetCollection(e).Items)
            CheckExpr(cg, item);
        break;
    default:
        break; // lambdas, sizeof, default(T), new T(): later steps
    }
}

// A name as a value (see EmitName).
Value CheckName(Compiler cg, Expr e)
{
    var n = cg.Tree.GetName(e);
    Value v = LookupVariable(cg, n.Name);
    if (!v.IsNone())
        return v;
    int owner = CurrentOwner(cg);
    if (owner != 0 && FindField(cg, owner, n.Name).Found)
    {
        if (cg.Fn[0].ThisSlot.Length == 0)
        {
            CheckError(cg, e.Loc, "'this' is not available in a static context");
            return UnknownValue(cg);
        }
        return CheckField(cg, Lvalue(owner, "%this", false), n.Name, e.Loc);
    }
    int c = LookupConst(cg, cg.Fn[0].File, n.Name);
    if (c >= 0)
        return EmitConst(cg, c, e.Loc);
    int g = LookupGlobal(cg, cg.Fn[0].File, n.Name);
    if (g >= 0)
        return GlobalUse(cg, g);
    if ((owner != 0 && MethodCandidates(cg, owner, n.Name).Length > 0) || FreeCandidates(cg, cg.Fn[0].File, n.Name).Length > 0)
        return UnknownValue(cg); // a function name as a value: converted by code generation for now
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

// Calls by name and methods of struct values (see EmitCallVia, EmitNameCall, EmitMemberCall).
Value CheckCall(Compiler cg, Expr e, bool viaStart)
{
    var call = cg.Tree.GetCall(e);
    bool known = true;
    if (call.Callee.Kind == ExprKind.Name)
        return CheckNameCall(cg, e, call, cg.Tree.GetName(call.Callee), viaStart);
    if (call.Callee.Kind == ExprKind.Member)
        return CheckMemberCall(cg, e, call, cg.Tree.GetMember(call.Callee), viaStart);
    CheckExpr(cg, call.Callee);
    CheckArgs(cg, call.Args, ref known);
    return UnknownValue(cg);
}

Value CheckNameCall(Compiler cg, Expr e, CallExpr call, NameExpr n, bool viaStart)
{
    bool known = true;
    Value variable = LookupVariable(cg, n.Name);
    if (!variable.IsNone())
    {
        if (!IsUnknown(cg, variable) && !IsCallableType(cg, variable.Type))
            CheckError(cg, e.Loc, "'" + n.Name + "' is a variable, not a function");
        CheckArgs(cg, call.Args, ref known);
        return UnknownValue(cg);
    }
    int owner = CurrentOwner(cg);
    if (owner != 0)
    {
        var fieldPath = FindField(cg, owner, n.Name);
        if (fieldPath.Found && IsCallableType(cg, fieldPath.Type))
        {
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
    var args = CheckArgs(cg, call.Args, ref known);
    if (cands.Length == 0)
    {
        CheckError(cg, e.Loc, "undefined function '" + n.Name + "'");
        return UnknownValue(cg);
    }
    if (!known)
        return UnknownValue(cg);
    string why = "";
    int instance = TryResolveOverload(cg, cands, args, ResolveTypeArgs(cg, n.TypeArgs), e.Loc, n.Name, ref why);
    if (instance < 0)
    {
        CheckError(cg, e.Loc, why);
        return UnknownValue(cg);
    }
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
    if (u.Op == UnOp.Deref || u.Op == UnOp.AddrOf)
    {
        CheckExpr(cg, u.Operand);
        return UnknownValue(cg);
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
        target = Lvalue(SliceElemType(cg, ht), "%e", false);
    }
    else
        target = CheckExpr(cg, a.Target);
    if (IsUnknown(cg, target))
    {
        CheckExpr(cg, a.Value);
        return target;
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
        CheckError(cg, e.Loc, "cannot assign to a read-only value (a constant or a 'const ref' parameter)");
        CheckExpr(cg, a.Value);
        return UnknownValue(cg);
    }
    Value rhs = CheckRValue(cg, a.Value);
    if (a.HasOp)
    {
        Value cur = target;
        cur.IsLValue = false;
        cur.IsConst = false;
        string why = "";
        int res = ArithmeticType(cg, a.Op, cur, rhs, ref why);
        if (res == 0)
            CheckError(cg, e.Loc, why);
        else if (res != target.Type && !(types.IsNumeric(res) && types.IsNumeric(target.Type)))
            CheckConversion(cg, Rvalue(res, "", false), target.Type, e.Loc);
    }
    else
        CheckConversion(cg, rhs, target.Type, a.Value.Loc);
    return Lvalue(target.Type, target.V, false);
}
