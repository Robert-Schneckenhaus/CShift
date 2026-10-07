// Expressions (port of CodeGenExpr.cpp). Calls are in Call.csh.
//
// Every emit function returns a Value: its type, the operand that holds it (or its address for an lvalue) and whether it
// carries a +1 reference count. The instructions are appended to the function that is being written.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// Every expression is written through here: the current location is the expression's own while it (and the checks
// after its operands) is written.
Value EmitExpr(const ref Compiler cg, Expr e)
{
    SourceLoc outer = cg.St[0].Loc;
    if (e.Loc.Line > 0)
        SetLoc(cg, e.Loc);
    Value v = EmitExprKind(cg, e);
    SetLoc(cg, outer);
    return v;
}

Value EmitExprKind(const ref Compiler cg, Expr e)
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
    case ExprKind.Slice: return EmitSlice(cg, e);
    case ExprKind.Embed:
    case ExprKind.EmbedFilenames:
    case ExprKind.EmbedLines:
        FailEmbedPlace(cg, e.Loc);
        return Value { };
    case ExprKind.NewArray: return EmitNewArray(cg, e);
    case ExprKind.Is: return EmitIs(cg, e);
    case ExprKind.Try: return EmitTry(cg, e);
    case ExprKind.ErrorLit: return EmitErrorLit(cg, e);
    case ExprKind.SizeOf:
    {
        int t = DeclTypeOf(cg, cg.Tree.GetSizeOf(e).Type);
        if (cg.Types.IsVoid(t))
            Fail(cg, e.Loc, "sizeof(void) is not defined");
        string size = SizeOfType(cg, t);
        return Rvalue(cg.Types.I32, SizeIr(cg) == "i32" ? size : "trunc (" + SizeIr(cg) + " " + size + " to i32)", false);
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
    case ExprKind.Lambda:
    {
        Value lambda = Rvalue(cg.Types.Lambda, "", false);
        lambda.LambdaNode = e;
        return lambda;
    }
    case ExprKind.Collection:
    {
        Value collection = Rvalue(cg.Types.Collection, "", false); // built when it is converted (Collections.csh)
        collection.CollectionNode = e;
        return collection;
    }
    case ExprKind.Conditional: return EmitConditionalIn(cg, e, 0);
    case ExprKind.Cast: return EmitCast(cg, e);
    case ExprKind.Start: return EmitStart(cg, e);
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

Value EmitRValue(const ref Compiler cg, Expr e)
{
    return ToRValue(cg, EmitExpr(cg, e));
}

// ---------------------------------------------------------------------------
// Literals, names
// ---------------------------------------------------------------------------

Value EmitLiteral(const ref Compiler cg, Expr e)
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
Value LookupVariable(const ref Compiler cg, string name)
{
    var vars = cg.Fn[0].Vars;
    for (var i = vars.Count(); i > 0; i -= 1)
    {
        if (vars.Get(i - 1).Name != name) // only the name is read (ElementField), not the whole variable
            continue;
        var v = vars.Get(i - 1);
        if (v.IsConstant)
            return ConstToValue(cg, v.ConstValue); // a local constant is inlined
        if (v.IsRef)
            return Lvalue(v.Type, cg.Ir.Load("ptr", v.Slot), v.IsConst);
        return Lvalue(v.Type, v.Slot, v.IsConst);
    }
    if (cg.Fn[0].LambdaId > 0)
        return CaptureVariable(cg, name); // a variable of an enclosing function, in the body of a lambda
    return Value { };
}

// The innermost local variable or constant with the name: its index in the variables, or -1.
int FindLocal(const ref Compiler cg, string name)
{
    var vars = cg.Fn[0].Vars;
    for (var i = vars.Count(); i > 0; i -= 1)
    {
        if (vars.Get(i - 1).Name == name)
            return i - 1;
    }
    return -1;
}

bool IsLocalName(const ref Compiler cg, string name)
{
    var vars = cg.Fn[0].Vars;
    for (var i = 0; i < vars.Count(); i += 1)
    {
        if (vars.Get(i).Name == name)
            return true;
    }
    return IsOuterName(cg, name);
}

Value EmitName(const ref Compiler cg, Expr e)
{
    var n = cg.Tree.GetName(e);
    Value moved = MoveLocal(cg, e); // the last use of a local variable: its reference is given away (Moves.csh)
    if (!moved.IsNone())
        return moved;
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
        return GlobalUse(cg, g);

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
    if (FindLocal(cg, n.Name + " (not assigned here)") >= 0)
        Fail(cg, e.Loc, "'" + n.Name + "' is not assigned here: 'x is not T " + n.Name + "' assigns it only where the pattern " +
                            "matched (the 'else' branch, or after the 'if' when its branch returns, breaks or continues)");
    Fail(cg, e.Loc, "undefined name '" + n.Name + "'");
    return Value { };
}

// A constant is inlined at every use: its value was computed by the compile-time evaluator (ConstEval.csh).
Value EmitConst(const ref Compiler cg, int index, SourceLoc loc)
{
    return ConstToValue(cg, ConstEvalDecl(cg, index));
}

// ---------------------------------------------------------------------------
// Checks that stop the program
// ---------------------------------------------------------------------------

// Where a panic happens, as a C string: "path:line:column in Function" (the current location, see EmitExpr). The path
// is the one the compiler was given; in a project it is relative to the project folder.
string PanicWhere(const ref Compiler cg)
{
    SourceLoc loc = cg.St[0].Loc;
    string where = "";
    if (loc.Line > 0 && loc.File >= 0 && loc.File < cg.Diag.Files.Count())
    {
        string path = cg.Diag.Files.Get(loc.File);
        string project = cg.St[0].ProjectDir;
        if (project.Length > 0 && project != "." && path.Length > project.Length + 1 && path.StartsWith(project) &&
            (path[project.Length] == '/' || path[project.Length] == '\\'))
            path = path.Substring(project.Length + 1);
        where = path + ":" + loc.Line.ToString() + ":" + loc.Col.ToString();
    }
    int fn = cg.Fn.Length > 0 ? cg.Fn[0].Func : -1;
    if (fn >= 0 && fn < cg.Instances.Count())
        where += (where.Length > 0 ? " in " : "in ") + cg.Instances.Get(fn).Name;
    return cg.Ir.CString(where.Length > 0 ? where : "unknown location");
}

// True while a function of the standard library is written.
bool InLibrary(const ref Compiler cg)
{
    if (cg.Fn.Length == 0)
        return false;
    int file = cg.Fn[0].File;
    return file >= 0 && file < cg.Files.Count() && cg.Files.Get(file).IsPrelude;
}

// A function of the standard library that calls Environment.Panic reports where the program called it: it has a second
// entry point (name.at) with the call site as a hidden last parameter. The plain entry point (for function values,
// method tables and the library itself) passes no call site.
bool ReportsCaller(const ref Compiler cg, FuncInfo fi)
{
    var d = cg.Funcs.Get(fi.Entry).Decl;
    return d.CallsPanic && !d.IsExtern && !d.IsThread && !d.Body.IsNull() && cg.Files.Get(fi.File).IsPrelude;
}

string CallerEntryName(string llvmName)
{
    if (llvmName.EndsWith("\""))
        return llvmName.Substring(0, llvmName.Length - 1) + ".at\"";
    return llvmName + ".at";
}

// The call site this function was given (a C string), or null.
string CallerOperand(const ref Compiler cg)
{
    if (cg.Fn.Length == 0 || cg.Fn[0].CallerArg == null || cg.Fn[0].CallerArg.Length == 0)
        return "null";
    return cg.Fn[0].CallerArg;
}

// Continues normally unless 'cond' is true: then the program panics with the message and where it happened.
void EmitPanicIf(const ref Compiler cg, string cond, string message)
{
    var ir = cg.Ir;
    string failLabel = ir.NewLabel("panic");
    string okLabel = ir.NewLabel("cont");
    ir.CondBr(cond, failLabel, okLabel);
    ir.SetBlock(failLabel);
    ir.Call("void", "@__cs_panic_at", "ptr " + ir.CString(message) + ", ptr " + PanicWhere(cg) + ", ptr " + CallerOperand(cg));
    ir.Unreachable();
    ir.SetBlock(okLabel);
}

// Like EmitPanicIf for an index check: the message also shows the index and the length (both sizes).
void EmitIndexPanicIf(const ref Compiler cg, string cond, string message, string index, string length)
{
    var ir = cg.Ir;
    string failLabel = ir.NewLabel("panic");
    string okLabel = ir.NewLabel("cont");
    ir.CondBr(cond, failLabel, okLabel);
    ir.SetBlock(failLabel);
    // the message prints both as int64 (%lld)
    index = SizeToI64(cg, index, true);
    length = SizeToI64(cg, length, true);
    ir.Call("void", "@__cs_panic_index", "ptr " + ir.CString(message) + ", i64 " + index + ", i64 " + length + ", ptr " + PanicWhere(cg) +
                                          ", ptr " + CallerOperand(cg));
    ir.Unreachable();
    ir.SetBlock(okLabel);
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

// An integer operation on two operands of the same type (checked unless in an 'unchecked' block).
string EmitIntOp(const ref Compiler cg, BinOp op, string l, string r, int t)
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
Value AsStringOperand(const ref Compiler cg, Value v, SourceLoc loc)
{
    var types = cg.Types;
    if (types.IsString(v.Type))
        return v;
    if (types.Kind(v.Type) == TypeKind.Null)
        return Rvalue(types.String, "null", false);
    return Rvalue(types.String, EmitToString(cg, v, loc), true);
}

// The bytes of a value that is appended to text (__cs_append): those of a string or a string slice itself, anything
// else as a new string. Temporaries are held until the end of the statement.
struct TextBytes
{
    string Data;
    string Length;
}

TextBytes TextBytesOf(const ref Compiler cg, Value v, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value r = ToRValue(cg, v);
    if (types.IsStringSlice(r.Type))
    {
        HoldTemp(cg, r);
        var p = PartsOf(cg, r);
        return TextBytes { Data = p.Data, Length = p.Length };
    }
    Value s = AsStringOperand(cg, r, loc);
    HoldTemp(cg, s);
    return TextBytes { Data = ir.Call("ptr", "@__cs_data", "ptr " + s.V), Length = ir.Call(SizeIr(cg), "@__cs_len", "ptr " + s.V) };
}

// text + bytes, giving up text (owned): written in place when text is the only reference to its block (__cs_append);
// 'grow' leaves room for more (text += ... in a loop).
string EmitAppend(const ref Compiler cg, string text, TextBytes bytes, bool grow)
{
    return cg.Ir.Call("ptr", "@__cs_append", "ptr " + text + ", ptr " + bytes.Data + ", " + SizeIr(cg) + " " + bytes.Length +
                                              ", i1 " + (grow ? "true" : "false"));
}

// Whether evaluating e cannot change a local variable: no assignment, 'ref' argument or address (&x) in it, only the
// kinds of expressions listed here (anything else counts as a change).
bool LeavesLocalsAlone(const ref Compiler cg, Expr e)
{
    var tree = cg.Tree;
    if (e.IsNull())
        return true;
    switch (e.Kind)
    {
    case ExprKind.IntLit:
    case ExprKind.FloatLit:
    case ExprKind.CharLit:
    case ExprKind.StringLit:
    case ExprKind.BoolLit:
    case ExprKind.NullLit:
    case ExprKind.Name:
    case ExprKind.This:
    case ExprKind.SizeOf:
    case ExprKind.Default:
        return true;
    case ExprKind.Member:
        return LeavesLocalsAlone(cg, tree.GetMember(e).Object);
    case ExprKind.Call:
    {
        var c = tree.GetCall(e);
        if (!LeavesLocalsAlone(cg, c.Callee))
            return false;
        foreach (var arg in c.Args)
        {
            if (!LeavesLocalsAlone(cg, arg))
                return false;
        }
        return true;
    }
    case ExprKind.Index:
        return LeavesLocalsAlone(cg, tree.GetIndex(e).Object) && LeavesLocalsAlone(cg, tree.GetIndex(e).Index);
    case ExprKind.Slice:
    {
        var s = tree.GetSlice(e);
        return LeavesLocalsAlone(cg, s.Object) && LeavesLocalsAlone(cg, s.Start) && LeavesLocalsAlone(cg, s.End);
    }
    case ExprKind.Binary:
        return LeavesLocalsAlone(cg, tree.GetBinary(e).Lhs) && LeavesLocalsAlone(cg, tree.GetBinary(e).Rhs);
    case ExprKind.Unary:
        return tree.GetUnary(e).Op != UnOp.AddrOf && LeavesLocalsAlone(cg, tree.GetUnary(e).Operand);
    case ExprKind.Conditional:
    {
        var c = tree.GetCond(e);
        return LeavesLocalsAlone(cg, c.Cond) && LeavesLocalsAlone(cg, c.Then) && LeavesLocalsAlone(cg, c.Else);
    }
    case ExprKind.Cast:
        return LeavesLocalsAlone(cg, tree.GetCast(e).Operand);
    case ExprKind.Unchecked:
        return LeavesLocalsAlone(cg, tree.GetUnchecked(e).Operand);
    case ExprKind.Try:
        return LeavesLocalsAlone(cg, tree.GetTry(e).Operand);
    default:
        return false;
    }
}

// What 'x += e' or 'x = x + e1 + e2 ...' appends to x, if x is a local string variable (or a parameter, not a 'ref'
// one) that none of the values can change - then x can be read after them and given to __cs_append. Empty otherwise.
Expr[] AppendedParts(const ref Compiler cg, AssignExpr a)
{
    var none = new Expr[0];
    if (a.Target.Kind != ExprKind.Name)
        return none;
    string name = cg.Tree.GetName(a.Target).Name;
    int local = FindLocal(cg, name);
    if (local < 0)
        return none;
    var v = cg.Fn[0].Vars.Get(local);
    if (v.IsRef || v.IsConst || v.IsConstant || !v.OwnsArc || !cg.Types.IsString(v.Type))
        return none;
    var parts = List<Expr>.Create();
    if (a.HasOp)
    {
        if (a.Op != BinOp.Add)
            return none;
        parts.Add(a.Value);
    }
    else
    {
        // x = x + e1 + e2: the left operands of the '+' lead to x
        var reversed = List<Expr>.Create();
        Expr cur = a.Value;
        while (cur.Kind == ExprKind.Binary && cg.Tree.GetBinary(cur).Op == BinOp.Add)
        {
            reversed.Add(cg.Tree.GetBinary(cur).Rhs);
            cur = cg.Tree.GetBinary(cur).Lhs;
        }
        if (cur.Kind != ExprKind.Name || cg.Tree.GetName(cur).Name != name || reversed.Count() == 0)
            return none;
        for (var i = reversed.Count(); i > 0; i -= 1)
            parts.Add(reversed.Get(i - 1));
    }
    foreach (var p in parts)
    {
        if (!LeavesLocalsAlone(cg, p))
            return none;
    }
    return parts.ToArray();
}

Value EmitArithmetic(const ref Compiler cg, BinOp op, Value l0, Value r0, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value l = ToRValue(cg, l0);
    Value r = ToRValue(cg, r0);
    string why = "";
    if (ArithmeticType(cg, op, l, r, ref why) == 0)
        Fail(cg, loc, why);

    // String concatenation (a string or a string slice and anything that has a text).
    if (IsTextJoin(cg, op, l.Type, r.Type))
    {
        Value a = AsStringOperand(cg, l, loc);
        // a temporary on the left (a call's result, the text of another '+') is given up: the right side is written
        // behind it in place when nothing else refers to it
        if (a.Owned && !a.IsLValue)
            return Rvalue(types.String, EmitAppend(cg, a.V, TextBytesOf(cg, r, loc), false), true);
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

Value EmitCompare(const ref Compiler cg, BinOp op, Value l0, Value r0, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value l = ToRValue(cg, l0);
    Value r = ToRValue(cg, r0);
    bool isEq = op == BinOp.Eq || op == BinOp.Ne;
    string why = "";
    if (CompareType(cg, op, l, r, ref why) == 0)
        Fail(cg, loc, why);

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
        if (k == TypeKind.Pointer || k == TypeKind.String || k == TypeKind.Array || k == TypeKind.CFunction)
            isNull = ir.ICmp("eq", "ptr", other.V, "null");
        else if (k == TypeKind.Function)
        {
            HoldTemp(cg, other);
            isNull = ir.ICmp("eq", "ptr", ir.ExtractValue("{ ptr, ptr }", other.V, "0"), "null");
        }
        else if (k == TypeKind.SharedPtr)
        {
            HoldTemp(cg, other);
            isNull = ir.ICmp("eq", "ptr", other.V, "null");
        }
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

    // A string slice compared with a string or another string slice: the bytes.
    if ((types.IsStringSlice(l.Type) || types.IsStringSlice(r.Type)) &&
        (types.IsString(l.Type) || types.IsStringSlice(l.Type)) && (types.IsString(r.Type) || types.IsStringSlice(r.Type)))
    {
        if (!isEq)
            Fail(cg, loc, "string slices can only be compared with '==' and '!='");
        return EmitTextEquals(cg, op, l, r);
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
        if (types.IsFunction(l.Type))
        {
            // the same function with the same environment
            HoldTemp(cg, l);
            HoldTemp(cg, r);
            string sameFn = ir.ICmp("eq", "ptr", ir.ExtractValue("{ ptr, ptr }", l.V, "0"), ir.ExtractValue("{ ptr, ptr }", r.V, "0"));
            string sameEnv = ir.ICmp("eq", "ptr", ir.ExtractValue("{ ptr, ptr }", l.V, "1"), ir.ExtractValue("{ ptr, ptr }", r.V, "1"));
            string same = ir.Bin("and", "i1", sameFn, sameEnv);
            return MakeBool(cg, op == BinOp.Eq ? same : ir.Bin("xor", "i1", same, "true"));
        }
        bool s = types.IsEnum(l.Type) && types.IsSigned(l.Type);
        return MakeBool(cg, ir.ICmp(IntPredicate(op, s), LlvmType(cg, l.Type), l.V, r.V));
    }

    // an error code compared with an integer ('e.Code == MyError.NotFound' for a plain Error<T>) is an int
    if (IsErrorEnum(cg, l.Type) && types.IsNumeric(r.Type))
        l = ConvertValue(cg, l, types.I32, loc);
    if (IsErrorEnum(cg, r.Type) && types.IsNumeric(l.Type))
        r = ConvertValue(cg, r, types.I32, loc);
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
Value EmitCondition(const ref Compiler cg, Expr e)
{
    Value v = EmitRValue(cg, e);
    string why = ConditionError(cg, v.Type);
    if (why.Length > 0)
        Fail(cg, e.Loc, why);
    return v;
}

// Error<T> and Optional<T> are not conditions ('if (x)', '!x', '&&', '?:'): what they test would be hidden. The code
// says it: 'x is error e' / 'x is T v' for a result, 'x is T v' / 'x == null' for an optional value.
void RejectAmbiguousCondition(const ref Compiler cg, int t, SourceLoc loc)
{
    string why = AmbiguousConditionError(cg, t);
    if (why.Length > 0)
        Fail(cg, loc, why);
}

// && and ||: the right side only runs if it can change the result.
// a && b, a || b: the right side only runs if it can change the result. A chain of the same operator (a || b || c ...)
// is written in a loop with one join block instead of by recursion, so that its length does not use up the stack.
Value EmitLogical(const ref Compiler cg, Expr e)
{
    var ir = cg.Ir;
    var b = cg.Tree.GetBinary(e);
    bool isAnd = b.Op == BinOp.LogAnd;
    var chain = List<Expr>.Create(); // e and the same operators on its left side, outermost first
    Expr leftmost = e;
    while (leftmost.Kind == ExprKind.Binary && cg.Tree.GetBinary(leftmost).Op == b.Op)
    {
        chain.Add(leftmost);
        leftmost = cg.Tree.GetBinary(leftmost).Lhs;
    }
    string current = EmitCondition(cg, leftmost).V;
    string endLabel = ir.NewLabel(isAnd ? "and.end" : "or.end");
    var incoming = StringBuilder.Create();
    for (var i = chain.Count() - 1; i >= 0; i -= 1)
    {
        var step = cg.Tree.GetBinary(chain.Get(i));
        string fromBlock = ir.CurrentBlock();
        string rhsLabel = ir.NewLabel(isAnd ? "and.rhs" : "or.rhs");
        if (isAnd)
            ir.CondBr(current, rhsLabel, endLabel);
        else
            ir.CondBr(current, endLabel, rhsLabel);
        incoming.Append("[ " + (isAnd ? "false" : "true") + ", %" + fromBlock + " ], ");

        ir.SetBlock(rhsLabel);
        int mark = cg.Fn[0].Temps.Count();
        current = EmitCondition(cg, step.Rhs).V;
        FlushTemps(cg, mark, true);
    }
    string lastBlock = ir.CurrentBlock();
    ir.Br(endLabel);
    ir.SetBlock(endLabel);
    incoming.Append("[ " + current + ", %" + lastBlock + " ]");
    return MakeBool(cg, ir.Phi("i1", incoming.ToString()));
}

// a op b. A left-deep chain (a + b + c + ..., as long string concatenations are) is written in a loop instead of by
// recursion, so that its length does not use up the stack; the order and every step are the same as with recursion.
Value EmitBinary(const ref Compiler cg, Expr e)
{
    var b = cg.Tree.GetBinary(e);
    if (b.Op == BinOp.LogAnd || b.Op == BinOp.LogOr)
        return EmitLogical(cg, e);
    var chain = List<Expr>.Create(); // e and the binary expressions on its left side, outermost first
    Expr leftmost = e;
    while (leftmost.Kind == ExprKind.Binary)
    {
        var lb = cg.Tree.GetBinary(leftmost);
        if (lb.Op == BinOp.LogAnd || lb.Op == BinOp.LogOr)
            break;
        chain.Add(leftmost);
        leftmost = lb.Lhs;
    }
    SourceLoc outer = cg.St[0].Loc;
    Value l = EmitRValue(cg, leftmost);
    for (var i = chain.Count() - 1; i >= 0; i -= 1)
    {
        Expr step = chain.Get(i);
        var sb = cg.Tree.GetBinary(step);
        Value r = EmitRValue(cg, sb.Rhs);
        if (step.Loc.Line > 0)
            SetLoc(cg, step.Loc);
        l = EmitBinaryStep(cg, sb.Op, l, r, step.Loc);
    }
    SetLoc(cg, outer);
    return l;
}

Value EmitBinaryStep(const ref Compiler cg, BinOp op, Value l, Value r, SourceLoc loc)
{
    switch (op)
    {
    case BinOp.Eq:
    case BinOp.Ne:
    case BinOp.Lt:
    case BinOp.Gt:
    case BinOp.Le:
    case BinOp.Ge:
        return EmitCompare(cg, op, l, r, loc);
    default:
        return EmitArithmetic(cg, op, l, r, loc);
    }
}

Value EmitUnary(const ref Compiler cg, Expr e)
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
    case UnOp.BitNot:
        return EmitUnaryOn(cg, u.Op, EmitRValue(cg, u.Operand), e.Loc);
    case UnOp.Not:
    {
        Value v = EmitRValue(cg, u.Operand);
        string why = "";
        if (UnaryResult(cg, u.Op, v, ref why).Type == 0)
            Fail(cg, e.Loc, why);
        if (types.IsBool(v.Type))
            return MakeBool(cg, ir.Bin("xor", "i1", v.V, "true"));
        RejectAmbiguousCondition(cg, v.Type, e.Loc);
        Fail(cg, e.Loc, "operator '!' cannot be applied to '" + types.Name(v.Type) + "'");
        return v;
    }
    default:
        Fail(cg, e.Loc, "cshc does not support pointers yet");
        return Value { };
    }
}

// -v, +v, ~v on a value (see EmitUnary).
Value EmitUnaryOn(const ref Compiler cg, UnOp op, Value v, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    string why = "";
    if (UnaryResult(cg, op, v, ref why).Type == 0)
        Fail(cg, loc, why);
    if (op == UnOp.BitNot)
    {
        if (types.IsEnum(v.Type))
            return Rvalue(v.Type, ir.Bin("xor", LlvmType(cg, v.Type), v.V, "-1"), false);
        if (!types.IsIntegral(v.Type))
            Fail(cg, loc, "operator '~' cannot be applied to '" + types.Name(v.Type) + "'");
        int bt = PromoteTypes(cg, v.Type, v.Type, loc);
        Value bc = ConvertValue(cg, v, bt, loc);
        return Rvalue(bt, ir.Bin("xor", LlvmType(cg, bt), bc.V, "-1"), false);
    }
    if (v.HasLit && op == UnOp.Neg)
        return NegateLiteral(cg, v);
    if (!types.IsNumeric(v.Type))
        Fail(cg, loc, "unary '-' cannot be applied to '" + types.Name(v.Type) + "'");
    int pt = types.IsFloat(v.Type) ? v.Type : PromoteTypes(cg, v.Type, v.Type, loc);
    Value c = ConvertValue(cg, v, pt, loc);
    if (op == UnOp.Plus)
        return c;
    if (types.IsFloat(pt))
        return Rvalue(pt, ir.Bin("fsub", LlvmType(cg, pt), FloatConstant(cg, pt, -0.0), c.V), false);
    if (!types.IsSigned(pt))
        Fail(cg, loc, "unary '-' cannot be applied to unsigned type '" + types.Name(pt) + "'");
    return Rvalue(pt, EmitIntOp(cg, BinOp.Sub, "0", c.V, pt), false);
}

// ---------------------------------------------------------------------------
// Target-typed integer arithmetic (see ArithmeticFrame in Rules.csh)
// ---------------------------------------------------------------------------

// An expression used as a value of 'target': integer arithmetic is computed in the target type where its operands
// allow; everything else is EmitExpr.
Value EmitExprAs(const ref Compiler cg, Expr e, int target)
{
    if (IsTypelessNew(cg, e))
        return EmitTypelessNew(cg, e, target);
    int frame = ArithmeticFrame(cg, target);
    if (frame == 0 || !IsFramable(cg, e))
        return EmitExpr(cg, e);
    return EmitFramed(cg, e, frame);
}

// The value of an operand of a framed expression.
Value EmitFramed(const ref Compiler cg, Expr e, int frame)
{
    if (!IsFramable(cg, e))
        return EmitRValue(cg, e);
    SourceLoc outer = cg.St[0].Loc;
    if (e.Loc.Line > 0)
        SetLoc(cg, e.Loc);
    Value v;
    if (e.Kind == ExprKind.Conditional)
        v = EmitConditionalIn(cg, e, frame);
    else if (e.Kind == ExprKind.Unchecked)
    {
        bool old = cg.Fn[0].Checked;
        cg.Fn[0].Checked = false;
        v = EmitFramed(cg, cg.Tree.GetUnchecked(e).Operand, frame);
        cg.Fn[0].Checked = old;
    }
    else if (e.Kind == ExprKind.Unary)
    {
        var u = cg.Tree.GetUnary(e);
        Value operand = EmitFramed(cg, u.Operand, frame);
        if (u.Op == UnOp.Neg && operand.HasLit)
            v = NegateLiteral(cg, operand);
        else if (FramedUnaryType(cg, u.Op, operand, frame) == frame)
        {
            Value c = ConvertValue(cg, AdaptLiteral(cg, operand, frame), frame, e.Loc);
            string res = u.Op == UnOp.Neg ? EmitIntOp(cg, BinOp.Sub, "0", c.V, frame) : cg.Ir.Bin("xor", LlvmType(cg, frame), c.V, "-1");
            v = Rvalue(frame, res, false);
        }
        else
            v = EmitUnaryOn(cg, u.Op, operand, e.Loc);
    }
    else
    {
        // a left-deep chain (a + b + c ...) in a loop, like EmitBinary
        var chain = List<Expr>.Create();
        Expr leftmost = e;
        while (leftmost.Kind == ExprKind.Binary && IsFramable(cg, leftmost))
        {
            chain.Add(leftmost);
            leftmost = cg.Tree.GetBinary(leftmost).Lhs;
        }
        v = EmitFramed(cg, leftmost, frame);
        for (var i = chain.Count() - 1; i >= 0; i -= 1)
        {
            Expr step = chain.Get(i);
            var sb = cg.Tree.GetBinary(step);
            // the count of a shift is not computed in the frame
            Value r = sb.Op == BinOp.Shl || sb.Op == BinOp.Shr ? EmitRValue(cg, sb.Rhs) : EmitFramed(cg, sb.Rhs, frame);
            if (step.Loc.Line > 0)
                SetLoc(cg, step.Loc);
            v = EmitFramedStep(cg, sb.Op, v, r, frame, step.Loc);
        }
    }
    SetLoc(cg, outer);
    return v;
}

// l op r in the frame if both fit, otherwise by the usual rules (EmitArithmetic).
Value EmitFramedStep(const ref Compiler cg, BinOp op, Value l, Value r, int frame, SourceLoc loc)
{
    bool folded = false;
    Value lit = FoldLiterals(cg, op, l, r, ref folded);
    if (folded)
        return lit;
    if (FramedArithmeticType(cg, op, l, r, frame) != frame)
        return EmitArithmetic(cg, op, l, r, loc);
    Value lc = ConvertValue(cg, AdaptLiteral(cg, l, frame), frame, loc);
    if (op == BinOp.Shl || op == BinOp.Shr)
        return Rvalue(frame, EmitIntOp(cg, op, lc.V, NumericConvert(cg, r.V, r.Type, frame), frame), false);
    Value rc = ConvertValue(cg, AdaptLiteral(cg, r, frame), frame, loc);
    return Rvalue(frame, EmitIntOp(cg, op, lc.V, rc.V, frame), false);
}

// target op= value: the result in the type of the target. A wider result (target = int16, value = int32) is narrowed;
// in checked code a value that does not fit is an overflow.
Value EmitCompound(const ref Compiler cg, BinOp op, Value cur, Expr value, SourceLoc loc)
{
    var types = cg.Types;
    int frame = ArithmeticFrame(cg, cur.Type);
    Value res;
    if (frame != 0 && types.IsIntegral(cur.Type))
        res = EmitFramedStep(cg, op, cur, EmitFramed(cg, value, frame), frame, loc);
    else
        res = EmitArithmetic(cg, op, cur, EmitRValue(cg, value), loc);
    if (res.Type == cur.Type || !types.IsNumeric(res.Type) || !types.IsNumeric(cur.Type))
        return res;
    return Rvalue(cur.Type, EmitNarrow(cg, res.V, res.Type, cur.Type), false);
}

// A number converted to another number type; between integer types checked (overflow panic) where the function is.
string EmitNarrow(const ref Compiler cg, string v, int from, int to)
{
    var types = cg.Types;
    string n = NumericConvert(cg, v, from, to);
    if (!cg.Fn[0].Checked || !types.IsIntegral(from) || !types.IsIntegral(to) || types.IsChar(from) || types.IsChar(to))
        return n;
    string back = NumericConvert(cg, n, to, from);
    EmitPanicIf(cg, cg.Ir.ICmp("ne", LlvmType(cg, from), back, v), "integer overflow");
    return n;
}

// ---------------------------------------------------------------------------
// Assignment, conditional, casts
// ---------------------------------------------------------------------------

Value EmitAssign(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    var a = cg.Tree.GetAssign(e);
    Value target;
    if (a.Target.Kind == ExprKind.Index)
    {
        // x[k] = v on a struct: x.Set(k, v); x[k] op= v: x.Set(k, x.Get(k) op v)
        var ix = cg.Tree.GetIndex(a.Target);
        Value holder = EmitExpr(cg, ix.Object);
        if (types.IsStruct(holder.Type))
        {
            // on a read-only value only if Get and Set keep it (EmitMethodCallOn reports it otherwise)
            // the key is used twice (Get and Set) and the values are passed on: each owned temporary is held once
            // here and passed on borrowed
            Value keyValue = EmitRValue(cg, ix.Index);
            HoldTemp(cg, keyValue);
            keyValue.Owned = false;
            var key = Arg { V = keyValue, Source = ix.Index };
            Value newValue;
            if (a.HasOp)
            {
                var getArgs = new Arg[1];
                getArgs[0] = key;
                Value cur = EmitMethodCallOn(cg, holder, "Get", getArgs, new int[0], e.Loc);
                HoldTemp(cg, cur);
                cur.Owned = false;
                newValue = EmitCompound(cg, a.Op, cur, a.Value, e.Loc);
            }
            else
                newValue = EmitRValue(cg, a.Value);
            HoldTemp(cg, newValue);
            newValue.Owned = false;
            EmitIndexerSet(cg, holder, key, newValue, e.Loc);
            return Rvalue(newValue.Type, newValue.V, false);
        }
        // arrays, strings and pointers: the element itself is the target
        if (types.IsStringSlice(holder.Type))
            Fail(cg, a.Target.Loc, "a StringSlice is read-only (strings are immutable)");
        if (types.IsReadOnlySlice(holder.Type))
            Fail(cg, a.Target.Loc, "a ReadOnlySlice is read-only (use an array or a Slice<T> to change elements)");
        target = EmitElement(cg, holder, ix.Index, ix.FromEnd, a.Target.Loc);
    }
    else
        target = EmitExpr(cg, a.Target);
    if (!target.IsLValue)
    {
        // a constant (local or top level) is a value, not a variable
        if (a.Target.Kind == ExprKind.Name)
        {
            string constName = cg.Tree.GetName(a.Target).Name;
            int local = FindLocal(cg, constName);
            bool isConstantName = local >= 0 ? cg.Fn[0].Vars.Get(local).IsConstant : LookupConst(cg, cg.Fn[0].File, constName) >= 0;
            if (isConstantName)
                Fail(cg, e.Loc, "cannot assign to a read-only value: '" + constName + "' is a constant");
        }
        Fail(cg, e.Loc, "the left side of an assignment must be a variable, field or element");
    }
    if (target.IsConst)
    {
        if (a.Target.Kind == ExprKind.Name && FindLocal(cg, cg.Tree.GetName(a.Target).Name) < 0 && IsOuterName(cg, cg.Tree.GetName(a.Target).Name))
            Fail(cg, e.Loc, "cannot assign to '" + cg.Tree.GetName(a.Target).Name + "': a lambda gets a read-only copy of the variables " +
                                "it uses (return the new value instead)");
        Fail(cg, e.Loc, "cannot assign to a read-only value (a constant or a 'const ref' parameter)");
    }

    // text += e (and text = text + e1 + e2 ...) on a local variable: its old text is given to __cs_append, which writes
    // behind it in place when the variable holds the only reference, with room to spare (a loop of appends is linear)
    var appended = AppendedParts(cg, a);
    if (appended.Length > 0)
    {
        var bytes = new TextBytes[appended.Length];
        for (var i = 0; i < appended.Length; i += 1)
            bytes[i] = TextBytesOf(cg, EmitRValue(cg, appended[i]), appended[i].Loc);
        string text = cg.Ir.Load("ptr", target.V);
        foreach (var b in bytes)
            text = EmitAppend(cg, text, b, true);
        StoreSlot(cg, target.Type, target.V, text, false); // the old text went to __cs_append
        return Lvalue(target.Type, target.V, false);
    }

    Value val;
    if (a.HasOp)
    {
        Value res = EmitCompound(cg, a.Op, ToRValue(cg, target), a.Value, e.Loc);
        val = res.Type == target.Type ? res : ConvertValue(cg, res, target.Type, e.Loc);
    }
    else
    {
        Value rhs = ToRValue(cg, EmitExprAs(cg, a.Value, target.Type));
        val = ConvertValue(cg, rhs, target.Type, a.Value.Loc);
    }

    string nv = Consume(cg, val);
    StoreSlot(cg, target.Type, target.V, nv, true);
    return Lvalue(target.Type, target.V, false);
}

// cond ? a : b; with a frame (see EmitFramed) the branches are computed in it.
Value EmitConditionalIn(const ref Compiler cg, Expr e, int frame)
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
    Value a = frame != 0 ? EmitFramed(cg, c.Then, frame) : EmitRValue(cg, c.Then);
    string thenEnd = ir.CurrentBlock();
    string thenCode = ir.TakeSince(thenMark);
    var thenTemps = TakeTemps(cg, baseCount);

    int elseMark = ir.Mark();
    ir.SetBlock(elseLabel);
    Value b = frame != 0 ? EmitFramed(cg, c.Else, frame) : EmitRValue(cg, c.Else);
    string elseEnd = ir.CurrentBlock();
    string elseCode = ir.TakeSince(elseMark);
    var elseTemps = TakeTemps(cg, baseCount);

    // The common type.
    string why = "";
    int t = ConditionalType(cg, a, b, ref why);
    if (t == 0)
        Fail(cg, e.Loc, why);

    // The then branch: its code, then the conversion, the temporaries and the jump to the end.
    ir.AppendCode(thenCode);
    ir.ResumeBlock(thenEnd);
    string av = Consume(cg, ConvertValue(cg, a, t, c.Then.Loc));
    // a conversion can make temporaries (an array that becomes a slice): they exist only in this branch
    ReleaseTemps(cg, TakeTemps(cg, baseCount));
    ReleaseTemps(cg, thenTemps);
    string thenFinal = ir.CurrentBlock();
    ir.Br(endLabel);

    ir.AppendCode(elseCode);
    ir.ResumeBlock(elseEnd);
    string bv = Consume(cg, ConvertValue(cg, b, t, c.Else.Loc));
    ReleaseTemps(cg, TakeTemps(cg, baseCount));
    ReleaseTemps(cg, elseTemps);
    string elseFinal = ir.CurrentBlock();
    ir.Br(endLabel);

    ir.SetBlock(endLabel);
    string incoming = "[ " + av + ", %" + thenFinal + " ], [ " + bv + ", %" + elseFinal + " ]";
    return Rvalue(t, ir.Phi(LlvmType(cg, t), incoming), NeedsArc(cg, t));
}

// Removes the temporaries above 'baseCount' from the list and returns them.
List<TempRelease> TakeTemps(const ref Compiler cg, int baseCount)
{
    var temps = cg.Fn[0].Temps;
    var taken = List<TempRelease>.Create();
    for (var i = baseCount; i < temps.Count(); i += 1)
        taken.Add(temps.Get(i));
    while (temps.Count() > baseCount)
        temps.RemoveAt(temps.Count() - 1);
    return taken;
}

void ReleaseTemps(const ref Compiler cg, List<TempRelease> list)
{
    for (var i = list.Count(); i > 0; i -= 1)
        ReleaseTemp(cg, list.Get(i - 1));
}

Value EmitCast(const ref Compiler cg, Expr e)
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
string EmitToString(const ref Compiler cg, Value value, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value v = ToRValue(cg, value);
    int t = v.Type;
    if (types.IsString(t))
        return Consume(cg, v);
    if (types.IsStringSlice(t))
        return StringSliceText(cg, v);
    if (types.IsBool(t))
    {
        string s = ir.Select(v.V, "ptr", "@.cs.true", "@.cs.false");
        ir.Call("void", "@__cs_retain", "ptr " + s);
        return s;
    }
    if (types.IsChar(t))
    {
        string r = ir.Call("ptr", "@__cs_alloc_text", SizeIr(cg) + " 2, " + SizeIr(cg) + " 1");
        string data = ir.ByteGep(r, HeaderSize(cg));
        ir.Store("i8", v.V, data);
        return r;
    }
    if (types.IsEnum(t))
        return ir.Call("ptr", EnumTextFunction(cg, t), LlvmType(cg, t) + " " + v.V); // the member's name
    if (types.IsInt(t))
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
    if (types.IsStruct(t))
    {
        // a struct with 'string ToString()' (like C#'s override of ToString)
        foreach (var c in MethodCandidates(cg, t, "ToString"))
        {
            var d = cg.Funcs.Get(c.Entry).Decl;
            if (!d.IsStatic && d.Params.Length == 0)
            {
                Value text = EmitMethodCallOn(cg, v, "ToString", new Arg[0], new int[0], loc);
                if (!types.IsString(text.Type))
                    Fail(cg, loc, "'" + types.Name(t) + ".ToString()' must return a string to be used as text");
                return Consume(cg, text);
            }
        }
        Fail(cg, loc, "cannot convert '" + types.Name(t) + "' to a string (give it a method 'string ToString()')");
    }
    Fail(cg, loc, "cannot convert '" + types.Name(t) + "' to a string");
    return v.V;
}
