// Expressions (port of CodeGenExpr.cpp). Calls are in Call.csh.
//
// Every emit function returns a Value: its type, the operand that holds it (or its address for an lvalue) and whether it
// carries a +1 reference count. The instructions are appended to the function that is being written.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

Value EmitExpr(Compiler cg, Expr e)
{
    switch (e.Kind)
    {
    case ExprKind.IntLit:
    case ExprKind.FloatLit:
    case ExprKind.CharLit:
    case ExprKind.StringLit:
    case ExprKind.BoolLit:
    case ExprKind.NullLit:
        return EmitLiteral(cg, e);
    case ExprKind.Name: return EmitName(cg, e);
    case ExprKind.Call: return EmitCall(cg, e);
    case ExprKind.Member: return EmitMember(cg, e);
    case ExprKind.Index: return EmitIndex(cg, e);
    case ExprKind.NewArray: return EmitNewArray(cg, e);
    case ExprKind.Is: return EmitIs(cg, e);
    case ExprKind.Try: return EmitTry(cg, e);
    case ExprKind.ErrorLit: return EmitErrorLit(cg, e);
    case ExprKind.SizeOf:
    {
        int t = DeclTypeOf(cg, cg.Tree.GetSizeOf(e).Type);
        if (cg.Types.IsVoid(t))
            Fail(cg, e.Loc, "sizeof(void) is not defined");
        return Rvalue(cg.Types.I32, "trunc (i64 " + SizeOfType(cg, t) + " to i32)", false);
    }
    case ExprKind.Default:
    {
        int t = DeclTypeOf(cg, cg.Tree.GetDefault(e).Type);
        if (cg.Types.IsVoid(t))
            Fail(cg, e.Loc, "default(void) is not defined");
        return Rvalue(t, ZeroValue(cg, t), false);
    }
    case ExprKind.Unchecked:
    {
        // integer overflow does not panic inside 'unchecked(...)'
        bool old = cg.Fn[0].Checked;
        cg.Fn[0].Checked = false;
        Value v = EmitExpr(cg, cg.Tree.GetUnchecked(e).Operand);
        cg.Fn[0].Checked = old;
        return v;
    }
    case ExprKind.StructInit: return EmitStructInit(cg, e);
    case ExprKind.NewObject: return EmitNewObject(cg, e);
    case ExprKind.This: return ThisValue(cg, e.Loc);
    case ExprKind.Unary: return EmitUnary(cg, e);
    case ExprKind.Binary: return EmitBinary(cg, e);
    case ExprKind.Assign: return EmitAssign(cg, e);
    case ExprKind.Conditional: return EmitConditional(cg, e);
    case ExprKind.Cast: return EmitCast(cg, e);
    case ExprKind.RefArg:
    {
        // 'ref x': the address of x is passed
        var n = cg.Tree.GetRefArg(e);
        Value o = EmitExpr(cg, n.Operand);
        if (!o.IsLValue)
            Fail(cg, e.Loc, "'ref' can only be applied to a variable, field or element");
        o.IsRefArg = true;
        return o;
    }
    default:
        Fail(cg, e.Loc, "cshc does not support this kind of expression yet (" + AstDumper.ExprKindName(e.Kind) + ")");
        return Value { };
    }
}

Value EmitRValue(Compiler cg, Expr e)
{
    return ToRValue(cg, EmitExpr(cg, e));
}

// ---------------------------------------------------------------------------
// Literals, names
// ---------------------------------------------------------------------------

Value EmitLiteral(Compiler cg, Expr e)
{
    var types = cg.Types;
    var tree = cg.Tree;
    switch (e.Kind)
    {
    case ExprKind.IntLit:
    {
        var l = tree.GetIntLit(e);
        if (l.IsUnsigned || l.IsLong)
        {
            int t;
            if (l.IsUnsigned && l.IsLong)
                t = types.U64;
            else if (l.IsUnsigned)
                t = l.Value <= 0xFFFFFFFFul ? types.U32 : types.U64;
            else
                t = l.Value <= 0x7FFFFFFFFFFFFFFFul ? types.I64 : types.U64;
            return ConstInt(cg, t, (int64)l.Value);
        }
        Value v;
        if (l.Value <= 0x7FFFFFFFul)
            v = ConstInt(cg, types.I32, (int64)l.Value);
        else if (l.Value <= 0x7FFFFFFFFFFFFFFFul)
            v = ConstInt(cg, types.I64, (int64)l.Value);
        else
            return ConstInt(cg, types.U64, (int64)l.Value);
        v.HasLit = true;
        v.LitInt = (int64)l.Value;
        return v;
    }
    case ExprKind.FloatLit:
    {
        var l = tree.GetFloatLit(e);
        int t = l.IsFloat32 ? types.F32 : types.F64;
        Value v = Rvalue(t, FloatConstant(cg, t, l.Value), false);
        if (!l.IsFloat32)
        {
            v.HasLit = true;
            v.LitIsFloat = true;
            v.LitFloat = l.Value;
        }
        return v;
    }
    case ExprKind.CharLit:
        return Rvalue(types.Char, tree.GetCharLit(e).Value.ToString(), false);
    case ExprKind.StringLit:
        return Rvalue(types.String, cg.Ir.StringLiteral(tree.GetStringLit(e).Value), false);
    case ExprKind.BoolLit:
        return MakeBool(cg, tree.GetBoolLit(e).Value ? "true" : "false");
    default:
        return Rvalue(types.Null, "null", false);
    }
}

// A local variable or parameter; the value has no type if there is none with that name.
Value LookupVariable(Compiler cg, string name)
{
    var vars = cg.Fn[0].Vars;
    for (var i = vars.Count(); i > 0; i -= 1)
    {
        var v = vars.Get(i - 1);
        if (v.Name != name)
            continue;
        if (v.IsRef)
            return Lvalue(v.Type, cg.Ir.Load("ptr", v.Slot), v.IsConst);
        return Lvalue(v.Type, v.Slot, v.IsConst);
    }
    return Value { };
}

bool IsLocalName(Compiler cg, string name)
{
    var vars = cg.Fn[0].Vars;
    for (var i = 0; i < vars.Count(); i += 1)
        if (vars.Get(i).Name == name)
            return true;
    return false;
}

Value EmitName(Compiler cg, Expr e)
{
    var n = cg.Tree.GetName(e);
    Value v = LookupVariable(cg, n.Name);
    if (!v.IsNone())
        return v;

    // A field of the current struct (in a method).
    int owner = CurrentOwner(cg);
    if (owner != 0 && FindField(cg, owner, n.Name).Found)
        return FieldAccess(cg, ThisValue(cg, e.Loc), n.Name, e.Loc);

    int c = LookupConst(cg, cg.Fn[0].File, n.Name);
    if (c >= 0)
        return EmitConst(cg, c, e.Loc);
    int g = LookupGlobal(cg, cg.Fn[0].File, n.Name);
    if (g >= 0)
        return GlobalValue(cg, g);

    // A function name is a value that converts to a matching Action/Func type.
    var group = new Candidate[0];
    if (owner != 0)
        group = MethodCandidates(cg, owner, n.Name);
    if (group.Length == 0)
        group = FreeCandidates(cg, cg.Fn[0].File, n.Name);
    if (group.Length > 0)
        return GroupValue(cg, group, ResolveTypeArgs(cg, n.TypeArgs), n.Name);
    if (!cg.St[0].StdlibLoaded && IsStdlibName(n.Name))
        Fail(cg, e.Loc, "cshc does not support the standard library yet ('" + n.Name + "')");
    Fail(cg, e.Loc, "undefined name '" + n.Name + "'");
    return Value { };
}

// Constant expressions: literals, operators and other constants.
bool IsConstExpr(Compiler cg, Expr e, int file)
{
    switch (e.Kind)
    {
    case ExprKind.IntLit:
    case ExprKind.FloatLit:
    case ExprKind.CharLit:
    case ExprKind.StringLit:
    case ExprKind.BoolLit:
        return true;
    case ExprKind.Name:
        return LookupConst(cg, file, cg.Tree.GetName(e).Name) >= 0;
    case ExprKind.Unary:
    {
        var u = cg.Tree.GetUnary(e);
        return u.Op != UnOp.Deref && u.Op != UnOp.AddrOf && IsConstExpr(cg, u.Operand, file);
    }
    case ExprKind.Binary:
    {
        var b = cg.Tree.GetBinary(e);
        return IsConstExpr(cg, b.Lhs, file) && IsConstExpr(cg, b.Rhs, file);
    }
    default:
        return false;
    }
}

// A constant is inlined at every use. Its initializer only consists of literals and other constants, so evaluating
// it has no side effects. It is evaluated in the file context of the declaration.
Value EmitConst(Compiler cg, int index, SourceLoc loc)
{
    var entry = cg.Consts.Get(index);
    var c = entry.Decl;
    if (!IsConstExpr(cg, c.Init, entry.File))
        Fail(cg, c.Loc, "the initializer of constant '" + c.Name + "' must be a constant expression (literals, operators, other constants)");
    int t = ResolveValueType(cg, c.Type.Id, entry.File, NoEnv());
    var types = cg.Types;
    if (!(types.IsNumeric(t) || types.IsBool(t) || types.IsString(t) || types.IsEnum(t)))
        Fail(cg, c.Loc, "constants can only be numbers, bool, char, string or enum values");
    int savedFile = cg.Fn[0].File;
    cg.Fn[0].File = entry.File;
    Value v;
    if (types.IsEnum(t))
    {
        // enumerators of imported C enums
        var noMembers = EnumInfo { Names = new string[0], Values = new int64[0] };
        v = ConstInt(cg, t, ConstEvalInt(cg, c.Init, noMembers, c.Loc));
    }
    else
    {
        v = ConvertValue(cg, EmitExpr(cg, c.Init), t, c.Init.Loc);
    }
    cg.Fn[0].File = savedFile;
    return v;
}

// ---------------------------------------------------------------------------
// Checks that stop the program
// ---------------------------------------------------------------------------

// Continues normally unless 'cond' is true: then the program panics with the message.
void EmitPanicIf(Compiler cg, string cond, string message)
{
    var ir = cg.Ir;
    string failLabel = ir.NewLabel("panic");
    string okLabel = ir.NewLabel("cont");
    ir.CondBr(cond, failLabel, okLabel);
    ir.SetBlock(failLabel);
    ir.Call("void", "@__cs_panic", "ptr " + ir.CString(message));
    ir.Unreachable();
    ir.SetBlock(okLabel);
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

// An integer operation on two operands of the same type (checked unless in an 'unchecked' block).
string EmitIntOp(Compiler cg, BinOp op, string l, string r, int t)
{
    var types = cg.Types;
    var ir = cg.Ir;
    bool isSigned = types.IsSigned(t);
    string ty = LlvmType(cg, t);
    int bits = types.Bits(t);

    switch (op)
    {
    case BinOp.Add:
    case BinOp.Sub:
    case BinOp.Mul:
    {
        string name = op == BinOp.Add ? "add" : (op == BinOp.Sub ? "sub" : "mul");
        if (!cg.Fn[0].Checked)
            return ir.Bin(name, ty, l, r);
        string intrinsic = "llvm." + (isSigned ? "s" : "u") + name + ".with.overflow." + ty;
        ir.Declare(intrinsic, "declare { " + ty + ", i1 } @" + intrinsic + "(" + ty + ", " + ty + ")");
        string res = ir.Call("{ " + ty + ", i1 }", "@" + intrinsic, ty + " " + l + ", " + ty + " " + r);
        string value = ir.ExtractValue("{ " + ty + ", i1 }", res, "0");
        string overflow = ir.ExtractValue("{ " + ty + ", i1 }", res, "1");
        EmitPanicIf(cg, overflow, "integer overflow");
        return value;
    }
    case BinOp.Div:
    case BinOp.Rem:
    {
        EmitPanicIf(cg, ir.ICmp("eq", ty, r, "0"), "division by zero");
        if (isSigned)
        {
            int64 one = 1;
            string minValue = bits >= 64 ? "-9223372036854775808" : (-(one << (bits - 1))).ToString();
            string isMin = ir.ICmp("eq", ty, l, minValue);
            string isMinusOne = ir.ICmp("eq", ty, r, "-1");
            EmitPanicIf(cg, ir.Bin("and", "i1", isMin, isMinusOne), "integer overflow");
            return ir.Bin(op == BinOp.Div ? "sdiv" : "srem", ty, l, r);
        }
        return ir.Bin(op == BinOp.Div ? "udiv" : "urem", ty, l, r);
    }
    case BinOp.BitAnd: return ir.Bin("and", ty, l, r);
    case BinOp.BitOr: return ir.Bin("or", ty, l, r);
    case BinOp.BitXor: return ir.Bin("xor", ty, l, r);
    case BinOp.Shl:
    case BinOp.Shr:
    {
        string count = ir.Bin("and", ty, r, (bits - 1).ToString());
        if (op == BinOp.Shl)
            return ir.Bin("shl", ty, l, count);
        return ir.Bin(isSigned ? "ashr" : "lshr", ty, l, count);
    }
    default:
        Fail(cg, SourceLoc { }, "internal error: invalid integer operation");
        return l;
    }
}

string BinOpText(BinOp op)
{
    switch (op)
    {
    case BinOp.Add: return "+";
    case BinOp.Sub: return "-";
    case BinOp.Mul: return "*";
    case BinOp.Div: return "/";
    case BinOp.Rem: return "%";
    case BinOp.BitAnd: return "&";
    case BinOp.BitOr: return "|";
    case BinOp.BitXor: return "^";
    case BinOp.Shl: return "<<";
    case BinOp.Shr: return ">>";
    default: return "?";
    }
}

// The value as a string for '+' (owned: a new string, or a retained one).
Value AsStringOperand(Compiler cg, Value v, SourceLoc loc)
{
    var types = cg.Types;
    if (types.IsString(v.Type))
        return v;
    if (types.Kind(v.Type) == TypeKind.Null)
        return Rvalue(types.String, "null", false);
    return Rvalue(types.String, EmitToString(cg, v, loc), true);
}

Value EmitArithmetic(Compiler cg, BinOp op, Value l0, Value r0, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value l = ToRValue(cg, l0);
    Value r = ToRValue(cg, r0);

    // String concatenation (the other operand may be any primitive).
    if (op == BinOp.Add && (types.IsString(l.Type) || types.IsString(r.Type)))
    {
        Value a = AsStringOperand(cg, l, loc);
        Value b = AsStringOperand(cg, r, loc);
        HoldTemp(cg, a);
        HoldTemp(cg, b);
        string res = ir.Call("ptr", "@__cs_concat", "ptr " + a.V + ", ptr " + b.V);
        return Rvalue(types.String, res, true);
    }

    if (types.IsPointer(l.Type) || types.IsPointer(r.Type))
        return EmitPointerArithmetic(cg, op, l, r, loc);

    // Bit operations on enums and bools.
    if (l.Type == r.Type && (op == BinOp.BitAnd || op == BinOp.BitOr || op == BinOp.BitXor))
    {
        if (types.IsEnum(l.Type) || types.IsBool(l.Type))
        {
            string name = op == BinOp.BitAnd ? "and" : (op == BinOp.BitOr ? "or" : "xor");
            return Rvalue(l.Type, ir.Bin(name, LlvmType(cg, l.Type), l.V, r.V), false);
        }
    }

    if (!types.IsNumeric(l.Type) || !types.IsNumeric(r.Type))
        Fail(cg, loc, "operator '" + BinOpText(op) + "' cannot be applied to '" + types.Name(l.Type) + "' and '" + types.Name(r.Type) + "'");

    // Shifts: the result has the (promoted) type of the left operand.
    if (op == BinOp.Shl || op == BinOp.Shr)
    {
        if (!types.IsIntegral(l.Type) || !types.IsIntegral(r.Type))
            Fail(cg, loc, "shift operators require integer operands");
        int st = PromoteTypes(cg, l.Type, l.Type, loc);
        Value lv = ConvertValue(cg, l.HasLit ? AdaptLiteral(cg, l, st) : l, st, loc);
        string count = NumericConvert(cg, r.V, r.Type, st);
        return Rvalue(st, EmitIntOp(cg, op, lv.V, count, st), false);
    }

    // Adapt literals to the other operand's type.
    if (l.HasLit && !r.HasLit)
        l = AdaptLiteral(cg, l, r.Type);
    else if (r.HasLit && !l.HasLit)
        r = AdaptLiteral(cg, r, l.Type);

    int t = PromoteTypes(cg, l.Type, r.Type, loc);
    Value lc = ConvertValue(cg, l, t, loc);
    Value rc = ConvertValue(cg, r, t, loc);

    if (types.IsFloat(t))
    {
        string ty = LlvmType(cg, t);
        string name;
        switch (op)
        {
        case BinOp.Add: name = "fadd"; break;
        case BinOp.Sub: name = "fsub"; break;
        case BinOp.Mul: name = "fmul"; break;
        case BinOp.Div: name = "fdiv"; break;
        case BinOp.Rem: name = "frem"; break;
        default:
            Fail(cg, loc, "bit operations are not defined for floating point values");
            name = "fadd";
            break;
        }
        return Rvalue(t, ir.Bin(name, ty, lc.V, rc.V), false);
    }
    return Rvalue(t, EmitIntOp(cg, op, lc.V, rc.V, t), false);
}

Value EmitCompare(Compiler cg, BinOp op, Value l0, Value r0, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value l = ToRValue(cg, l0);
    Value r = ToRValue(cg, r0);
    bool isEq = op == BinOp.Eq || op == BinOp.Ne;

    // A function name compared with a function value takes the function's type.
    if (types.Kind(l.Type) == TypeKind.MethodGroup && types.IsFunction(r.Type))
        l = ConvertValue(cg, l, r.Type, loc);
    else if (types.Kind(r.Type) == TypeKind.MethodGroup && types.IsFunction(l.Type))
        r = ConvertValue(cg, r, l.Type, loc);

    // Comparisons with null.
    if (types.Kind(l.Type) == TypeKind.Null || types.Kind(r.Type) == TypeKind.Null)
    {
        if (!isEq)
            Fail(cg, loc, "null can only be compared with '==' and '!='");
        Value other = types.Kind(l.Type) == TypeKind.Null ? r : l;
        string isNull;
        var k = types.Kind(other.Type);
        if (k == TypeKind.Pointer || k == TypeKind.String || k == TypeKind.Array || k == TypeKind.Function)
            isNull = ir.ICmp("eq", "ptr", other.V, "null");
        else if (k == TypeKind.Optional)
        {
            HoldTemp(cg, other);
            isNull = ir.Bin("xor", "i1", ir.ExtractValue(LlvmType(cg, other.Type), other.V, "0"), "true");
        }
        else if (k == TypeKind.Null)
            isNull = "true";
        else
        {
            Fail(cg, loc, "type '" + types.Name(other.Type) + "' cannot be compared with null");
            isNull = "true";
        }
        return MakeBool(cg, op == BinOp.Eq ? isNull : ir.Bin("xor", "i1", isNull, "true"));
    }

    // String equality.
    if (types.IsString(l.Type) && types.IsString(r.Type))
    {
        if (!isEq)
            Fail(cg, loc, "strings can only be compared with '==' and '!='");
        HoldTemp(cg, l);
        HoldTemp(cg, r);
        string eq = ir.Call("i1", "@__cs_streq", "ptr " + l.V + ", ptr " + r.V);
        return MakeBool(cg, op == BinOp.Eq ? eq : ir.Bin("xor", "i1", eq, "true"));
    }

    if (l.HasLit && !r.HasLit)
        l = AdaptLiteral(cg, l, r.Type);
    else if (r.HasLit && !l.HasLit)
        r = AdaptLiteral(cg, r, l.Type);

    // Bool, enum, pointer.
    if (l.Type == r.Type && (types.IsBool(l.Type) || types.IsEnum(l.Type) || types.IsPointer(l.Type) || types.IsFunction(l.Type)))
    {
        if ((types.IsBool(l.Type) || types.IsFunction(l.Type)) && !isEq)
            Fail(cg, loc, types.IsBool(l.Type) ? "bool values can only be compared with '==' and '!='"
                                                 : "function values can only be compared with '==' and '!='");
        bool s = types.IsEnum(l.Type) && types.IsSigned(l.Type);
        return MakeBool(cg, ir.ICmp(IntPredicate(op, s), LlvmType(cg, l.Type), l.V, r.V));
    }

    if (!types.IsNumeric(l.Type) || !types.IsNumeric(r.Type))
        Fail(cg, loc, "cannot compare '" + types.Name(l.Type) + "' with '" + types.Name(r.Type) + "'");

    int t = PromoteTypes(cg, l.Type, r.Type, loc);
    Value lv = ConvertValue(cg, l, t, loc);
    Value rv = ConvertValue(cg, r, t, loc);
    string ty = LlvmType(cg, t);
    if (types.IsFloat(t))
    {
        string pred;
        switch (op)
        {
        case BinOp.Eq: pred = "oeq"; break;
        case BinOp.Ne: pred = "une"; break;
        case BinOp.Lt: pred = "olt"; break;
        case BinOp.Gt: pred = "ogt"; break;
        case BinOp.Le: pred = "ole"; break;
        default: pred = "oge"; break;
        }
        return MakeBool(cg, ir.FCmp(pred, ty, lv.V, rv.V));
    }
    return MakeBool(cg, ir.ICmp(IntPredicate(op, types.IsSigned(t)), ty, lv.V, rv.V));
}

string IntPredicate(BinOp op, bool isSigned)
{
    switch (op)
    {
    case BinOp.Eq: return "eq";
    case BinOp.Ne: return "ne";
    case BinOp.Lt: return isSigned ? "slt" : "ult";
    case BinOp.Gt: return isSigned ? "sgt" : "ugt";
    case BinOp.Le: return isSigned ? "sle" : "ule";
    default: return isSigned ? "sge" : "uge";
    }
}

// A condition must be a bool.
Value EmitCondition(Compiler cg, Expr e)
{
    Value v = EmitRValue(cg, e);
    if (cg.Types.IsBool(v.Type))
        return v;
    if (cg.Types.IsResultLike(v.Type))
    {
        HoldTemp(cg, v);
        return MakeBool(cg, cg.Ir.ExtractValue(LlvmType(cg, v.Type), v.V, "0"));
    }
    Fail(cg, e.Loc, "a condition must be of type 'bool', not '" + cg.Types.Name(v.Type) + "' (there is no implicit conversion to bool)");
    return v;
}

// && and ||: the right side only runs if it can change the result.
Value EmitLogical(Compiler cg, Expr e)
{
    var ir = cg.Ir;
    var b = cg.Tree.GetBinary(e);
    bool isAnd = b.Op == BinOp.LogAnd;
    Value l = EmitCondition(cg, b.Lhs);
    string lhsEnd = ir.CurrentBlock();
    string rhsLabel = ir.NewLabel(isAnd ? "and.rhs" : "or.rhs");
    string endLabel = ir.NewLabel(isAnd ? "and.end" : "or.end");
    if (isAnd)
        ir.CondBr(l.V, rhsLabel, endLabel);
    else
        ir.CondBr(l.V, endLabel, rhsLabel);

    ir.SetBlock(rhsLabel);
    int mark = cg.Fn[0].Temps.Count();
    Value r = EmitCondition(cg, b.Rhs);
    FlushTemps(cg, mark, true);
    string rhsEnd = ir.CurrentBlock();
    ir.Br(endLabel);

    ir.SetBlock(endLabel);
    string incoming = "[ " + (isAnd ? "false" : "true") + ", %" + lhsEnd + " ], [ " + r.V + ", %" + rhsEnd + " ]";
    return MakeBool(cg, ir.Phi("i1", incoming));
}

Value EmitBinary(Compiler cg, Expr e)
{
    var b = cg.Tree.GetBinary(e);
    if (b.Op == BinOp.LogAnd || b.Op == BinOp.LogOr)
        return EmitLogical(cg, e);
    Value l = EmitRValue(cg, b.Lhs);
    Value r = EmitRValue(cg, b.Rhs);
    switch (b.Op)
    {
    case BinOp.Eq:
    case BinOp.Ne:
    case BinOp.Lt:
    case BinOp.Gt:
    case BinOp.Le:
    case BinOp.Ge:
        return EmitCompare(cg, b.Op, l, r, e.Loc);
    default:
        return EmitArithmetic(cg, b.Op, l, r, e.Loc);
    }
}

Value EmitUnary(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var u = cg.Tree.GetUnary(e);
    switch (u.Op)
    {
    case UnOp.Deref:
        return DerefPointer(cg, EmitExpr(cg, u.Operand), e.Loc);
    case UnOp.AddrOf:
        return EmitAddressOf(cg, e, u.Operand);
    case UnOp.Neg:
    case UnOp.Plus:
    {
        Value v = EmitRValue(cg, u.Operand);
        if (v.HasLit && u.Op == UnOp.Neg)
        {
            if (v.LitIsFloat)
            {
                Value f = Rvalue(v.Type, FloatConstant(cg, v.Type, -v.LitFloat), false);
                f.HasLit = true;
                f.LitIsFloat = true;
                f.LitFloat = -v.LitFloat;
                return f;
            }
            int64 n = -v.LitInt;
            int t = (n >= -2147483648 && n <= 2147483647) ? types.I32 : types.I64;
            Value r = ConstInt(cg, t, n);
            r.HasLit = true;
            r.LitInt = n;
            return r;
        }
        if (!types.IsNumeric(v.Type))
            Fail(cg, e.Loc, "unary '-' cannot be applied to '" + types.Name(v.Type) + "'");
        int pt = types.IsFloat(v.Type) ? v.Type : PromoteTypes(cg, v.Type, v.Type, e.Loc);
        Value c = ConvertValue(cg, v, pt, e.Loc);
        if (u.Op == UnOp.Plus)
            return c;
        if (types.IsFloat(pt))
            return Rvalue(pt, ir.Bin("fsub", LlvmType(cg, pt), FloatConstant(cg, pt, -0.0), c.V), false);
        if (!types.IsSigned(pt))
            Fail(cg, e.Loc, "unary '-' cannot be applied to unsigned type '" + types.Name(pt) + "'");
        return Rvalue(pt, EmitIntOp(cg, BinOp.Sub, "0", c.V, pt), false);
    }
    case UnOp.Not:
    {
        Value v = EmitRValue(cg, u.Operand);
        if (types.IsBool(v.Type))
            return MakeBool(cg, ir.Bin("xor", "i1", v.V, "true"));
        if (types.IsResultLike(v.Type))
        {
            HoldTemp(cg, v);
            return MakeBool(cg, ir.Bin("xor", "i1", ir.ExtractValue(LlvmType(cg, v.Type), v.V, "0"), "true"));
        }
        Fail(cg, e.Loc, "operator '!' cannot be applied to '" + types.Name(v.Type) + "'");
        return v;
    }
    case UnOp.BitNot:
    {
        Value v = EmitRValue(cg, u.Operand);
        if (types.IsEnum(v.Type))
            return Rvalue(v.Type, ir.Bin("xor", LlvmType(cg, v.Type), v.V, "-1"), false);
        if (!types.IsIntegral(v.Type))
            Fail(cg, e.Loc, "operator '~' cannot be applied to '" + types.Name(v.Type) + "'");
        int pt = PromoteTypes(cg, v.Type, v.Type, e.Loc);
        Value c = ConvertValue(cg, v, pt, e.Loc);
        return Rvalue(pt, ir.Bin("xor", LlvmType(cg, pt), c.V, "-1"), false);
    }
    default:
        Fail(cg, e.Loc, "cshc does not support pointers yet");
        return Value { };
    }
}

// ---------------------------------------------------------------------------
// Assignment, conditional, casts
// ---------------------------------------------------------------------------

Value EmitAssign(Compiler cg, Expr e)
{
    var types = cg.Types;
    var a = cg.Tree.GetAssign(e);
    Value target = EmitExpr(cg, a.Target);
    if (!target.IsLValue)
        Fail(cg, e.Loc, "the left side of an assignment must be a variable, field or element");
    if (target.IsConst)
        Fail(cg, e.Loc, "cannot assign to a read-only value ('const ref' parameter)");

    Value val;
    if (a.HasOp)
    {
        Value cur = ToRValue(cg, target);
        Value rhs = EmitRValue(cg, a.Value);
        Value res = EmitArithmetic(cg, a.Op, cur, rhs, e.Loc);
        if (res.Type == target.Type)
            val = res;
        else if (types.IsNumeric(res.Type) && types.IsNumeric(target.Type))
            val = Rvalue(target.Type, NumericConvert(cg, res.V, res.Type, target.Type), false);
        else
            val = ConvertValue(cg, res, target.Type, e.Loc);
    }
    else
    {
        Value rhs = EmitRValue(cg, a.Value);
        val = ConvertValue(cg, rhs, target.Type, a.Value.Loc);
    }

    string nv = Consume(cg, val);
    StoreSlot(cg, target.Type, target.V, nv, true);
    return Lvalue(target.Type, target.V, false);
}

Value EmitConditional(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var c = cg.Tree.GetCond(e);
    Value cond = EmitCondition(cg, c.Cond);
    string thenLabel = ir.NewLabel("cond.then");
    string elseLabel = ir.NewLabel("cond.else");
    string endLabel = ir.NewLabel("cond.end");
    ir.CondBr(cond.V, thenLabel, elseLabel);

    var temps = cg.Fn[0].Temps;
    int baseCount = temps.Count();

    // Both branches are generated first; the conversions to the common type are added at their ends afterwards.
    int thenMark = ir.Mark();
    ir.SetBlock(thenLabel);
    Value a = EmitRValue(cg, c.Then);
    string thenEnd = ir.CurrentBlock();
    string thenCode = ir.TakeSince(thenMark);
    var thenTemps = TakeTemps(cg, baseCount);

    int elseMark = ir.Mark();
    ir.SetBlock(elseLabel);
    Value b = EmitRValue(cg, c.Else);
    string elseEnd = ir.CurrentBlock();
    string elseCode = ir.TakeSince(elseMark);
    var elseTemps = TakeTemps(cg, baseCount);

    // The common type.
    int t;
    if (a.Type == b.Type)
        t = a.Type;
    else if (ConversionCost(cg, a, b.Type) >= 0 && (ConversionCost(cg, b, a.Type) < 0 || a.HasLit))
        t = b.Type;
    else if (ConversionCost(cg, b, a.Type) >= 0)
        t = a.Type;
    else
    {
        Fail(cg, e.Loc, "the branches of '?:' have incompatible types '" + types.Name(a.Type) + "' and '" + types.Name(b.Type) + "'");
        t = a.Type;
    }
    if (types.Kind(t) == TypeKind.Null)
        Fail(cg, e.Loc, "cannot infer the type of a conditional expression with only null");
    if (types.IsVoid(t))
        Fail(cg, e.Loc, "conditional branches cannot be void");

    // The then branch: its code, then the conversion, the temporaries and the jump to the end.
    ir.AppendCode(thenCode);
    ir.ResumeBlock(thenEnd);
    string av = Consume(cg, ConvertValue(cg, a, t, c.Then.Loc));
    ReleaseTemps(cg, thenTemps);
    string thenFinal = ir.CurrentBlock();
    ir.Br(endLabel);

    ir.AppendCode(elseCode);
    ir.ResumeBlock(elseEnd);
    string bv = Consume(cg, ConvertValue(cg, b, t, c.Else.Loc));
    ReleaseTemps(cg, elseTemps);
    string elseFinal = ir.CurrentBlock();
    ir.Br(endLabel);

    ir.SetBlock(endLabel);
    string incoming = "[ " + av + ", %" + thenFinal + " ], [ " + bv + ", %" + elseFinal + " ]";
    return Rvalue(t, ir.Phi(LlvmType(cg, t), incoming), NeedsArc(cg, t));
}

// Removes the temporaries above 'baseCount' from the list and returns them.
List<TempRelease> TakeTemps(Compiler cg, int baseCount)
{
    var temps = cg.Fn[0].Temps;
    var taken = List<TempRelease>.Create();
    for (var i = baseCount; i < temps.Count(); i += 1)
        taken.Add(temps.Get(i));
    while (temps.Count() > baseCount)
        temps.RemoveAt(temps.Count() - 1);
    return taken;
}

void ReleaseTemps(Compiler cg, List<TempRelease> list)
{
    for (var i = list.Count(); i > 0; i -= 1)
    {
        var t = list.Get(i - 1);
        EmitRelease(cg, t.Type, t.Value);
    }
}

Value EmitCast(Compiler cg, Expr e)
{
    var types = cg.Types;
    var c = cg.Tree.GetCast(e);
    int to = DeclTypeOf(cg, c.Type);
    Value v = EmitRValue(cg, c.Operand);
    int from = v.Type;
    if (from == to)
        return v;
    if (ConversionCost(cg, v, to) >= 0)
        return ConvertValue(cg, v, to, e.Loc);

    bool fromNumeric = types.IsInt(from) || types.IsChar(from) || types.IsEnum(from) || types.IsFloat(from);
    bool toNumeric = types.IsInt(to) || types.IsChar(to) || types.IsEnum(to) || types.IsFloat(to);
    if (fromNumeric && toNumeric)
    {
        if (types.IsEnum(from) && types.IsFloat(to))
            Fail(cg, e.Loc, "cannot cast an enum to a floating point type");
        return Rvalue(to, NumericConvert(cg, v.V, from, to), false);
    }
    var casted = Value { };
    if (EmitPointerCast(cg, v, to, e.Loc, ref casted))
        return casted;
    Fail(cg, e.Loc, "cannot cast '" + types.Name(from) + "' to '" + types.Name(to) + "'");
    return v;
}

// ---------------------------------------------------------------------------
// Conversion to text
// ---------------------------------------------------------------------------

// The value as a string with a +1 reference count.
string EmitToString(Compiler cg, Value value, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value v = ToRValue(cg, value);
    int t = v.Type;
    if (types.IsString(t))
        return Consume(cg, v);
    if (types.IsBool(t))
    {
        string s = ir.Select(v.V, "ptr", "@.cs.true", "@.cs.false");
        ir.Call("void", "@__cs_retain", "ptr " + s);
        return s;
    }
    if (types.IsChar(t))
    {
        string r = ir.Call("ptr", "@__cs_alloc", "i64 2, i64 1");
        string data = ir.ByteGep(r, "16");
        ir.Store("i8", v.V, data);
        return r;
    }
    if (types.IsEnum(t) || types.IsInt(t))
    {
        bool isSigned = types.IsSigned(t);
        string src = LlvmType(cg, t);
        string wide = types.Bits(t) == 64 ? v.V : ir.Cast(isSigned ? "sext" : "zext", src, v.V, "i64");
        return ir.Call("ptr", isSigned ? "@__cs_fmt_i64" : "@__cs_fmt_u64", "i64 " + wide);
    }
    if (types.IsFloat(t))
    {
        if (types.Bits(t) == 32)
        {
            string wide = ir.Cast("fpext", "float", v.V, "double");
            return ir.Call("ptr", "@__cs_fmt_f32", "double " + wide);
        }
        return ir.Call("ptr", "@__cs_fmt_f64", "double " + v.V);
    }
    Fail(cg, loc, "cannot convert '" + types.Name(t) + "' to a string");
    return v.V;
}
