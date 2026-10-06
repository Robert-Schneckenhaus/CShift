// The compile-time evaluator: the value of a constant expression is computed by the compiler, not by generated code
// (port of compiler/src/ConstEval.cpp; both must give the same results).
//
// It follows the rules of the code that is generated for the same expression at run time (the type of literals, the
// promotion of small integers, checked arithmetic, shifts, comparisons, conversions, string concatenation), but an
// overflow or a division by zero is an error of the compilation. Constants (top level and local), the values of enum
// members and sizeof(T) are evaluated with it.
//
// Integers are kept as sign and magnitude (the value of every integer type fits into a 64 bit magnitude), so no wider
// integer type is needed.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;
using System.Native;

extern "C" int snprintf(char* buffer, nuint size, char* format, ...);

// Unknown: the value of a constant whose type or initializer had an error (reported once); everything computed from it is
// unknown too, and nothing about it is reported.
enum ConstKind : int32 { Int, Float, Bool, String, Slice, Unknown }

struct ConstVal
{
    ConstKind Kind;
    int Type;
    bool Neg;          // Int (also char and enum): sign and magnitude
    uint64 Mag;
    double F;          // Float (a float32 holds a value that is exactly representable as float)
    bool B;            // Bool
    string S;          // String
    ConstVal[] Items;  // Slice: the elements (Type is ReadOnlySlice<T>, or Collection before it gets its type)
    bool HasLit;       // an unsuffixed literal: adapts to the type of the value it is combined with
}

// What a constant expression may refer to.
struct ConstScope
{
    int File;                          // names are looked up from this file
    bool Locals;                       // the local constants of the function that is being written are visible
    bool HasEnum;                      // the enum whose members are being declared: its earlier members are visible
    EnumInfo Enum;
    string What;                       // for error messages: "constant 'X'" or "enum member 'X'"
    SourceLoc DeclLoc;
    Dictionary<string, int> Env;       // type parameters (for casts and sizeof in generic functions)
}

struct SignMag
{
    bool Neg;
    uint64 Mag;
    bool Ok;
}

// ---------------------------------------------------------------------------
// Integers as sign and magnitude
// ---------------------------------------------------------------------------

uint64 ConstMask(int bits)
{
    if (bits >= 64)
        return 0xFFFFFFFFFFFFFFFFul;
    return (1ul << bits) - 1ul;
}

bool ConstSignedType(const ref Compiler cg, int t)
{
    var types = cg.Types;
    return (types.IsInt(t) || types.IsEnum(t)) && types.IsSigned(t);
}

bool ConstIntLike(const ref Compiler cg, int t)
{
    var types = cg.Types;
    return types.IsInt(t) || types.IsChar(t) || types.IsEnum(t);
}

// The two's complement bits of an integer value, in 'bits' bits.
uint64 ConstPattern(ConstVal v, int bits)
{
    uint64 p = v.Mag;
    if (v.Neg && v.Mag != 0)
        p = unchecked(~v.Mag + 1);
    return p & ConstMask(bits);
}

// An integer value of a type from two's complement bits.
ConstVal ConstFromPattern(const ref Compiler cg, int type, uint64 pattern)
{
    var v = ConstVal { Kind = ConstKind.Int, Type = type };
    int bits = cg.Types.Bits(type);
    uint64 p = pattern & ConstMask(bits);
    if (ConstSignedType(cg, type) && bits > 0 && ((p >> (bits - 1)) & 1ul) == 1ul)
    {
        v.Neg = true;
        v.Mag = unchecked(~p + 1) & ConstMask(bits);
    }
    else
    {
        v.Mag = p;
    }
    return v;
}

bool ConstFits(const ref Compiler cg, ConstVal v, int t)
{
    int bits = cg.Types.Bits(t);
    if (ConstSignedType(cg, t))
    {
        uint64 limit = 1ul << (bits - 1);
        return v.Neg ? v.Mag <= limit : v.Mag < limit;
    }
    return (!v.Neg || v.Mag == 0) && v.Mag <= ConstMask(bits);
}

string ConstDecimal(ConstVal v)
{
    return (v.Neg && v.Mag != 0 ? "-" : "") + v.Mag.ToString();
}

ConstVal ConstMakeInt(int type, bool neg, uint64 mag, bool lit)
{
    return ConstVal { Kind = ConstKind.Int, Type = type, Neg = neg && mag != 0, Mag = mag, HasLit = lit };
}

ConstVal ConstMakeFloat(const ref Compiler cg, int type, double f, bool lit)
{
    double value = f;
    if (cg.Types.Bits(type) == 32)
        value = (double)(float)f;
    return ConstVal { Kind = ConstKind.Float, Type = type, F = value, HasLit = lit };
}

ConstVal ConstMakeBool(const ref Compiler cg, bool b)
{
    return ConstVal { Kind = ConstKind.Bool, Type = cg.Types.Bool, B = b };
}

// The value of an integer as a floating point number (a float32 is rounded once, directly from the integer).
double ConstToFloat(const ref Compiler cg, ConstVal v, int to)
{
    double m = (double)v.Mag;
    if (cg.Types.Bits(to) == 32)
        m = (double)(float)v.Mag;
    return v.Neg ? -m : m;
}

SignMag ConstAddSigned(bool an, uint64 am, bool bn, uint64 bm)
{
    var r = SignMag { Ok = true };
    if (an == bn)
    {
        r.Neg = an;
        r.Mag = unchecked(am + bm);
        r.Ok = r.Mag >= am;
        return r;
    }
    if (am >= bm)
    {
        r.Neg = an;
        r.Mag = am - bm;
    }
    else
    {
        r.Neg = bn;
        r.Mag = bm - am;
    }
    if (r.Mag == 0)
        r.Neg = false;
    return r;
}

// The order of two integer values: -1, 0 or 1.
int ConstOrder(ConstVal a, ConstVal b)
{
    bool an = a.Neg && a.Mag != 0;
    bool bn = b.Neg && b.Mag != 0;
    if (an != bn)
        return an ? -1 : 1;
    if (a.Mag == b.Mag)
        return 0;
    return ((a.Mag < b.Mag) != an) ? -1 : 1;
}

// A floating point number converted to an integer type: truncated and clamped to the range (NaN gives 0), like the
// llvm.fptosi.sat / fptoui.sat intrinsics that the generated code uses.
ConstVal ConstSaturate(const ref Compiler cg, double d, int to)
{
    var r = ConstVal { Kind = ConstKind.Int, Type = to };
    int bits = cg.Types.Bits(to);
    if (d != d)
        return r;
    if (ConstSignedType(cg, to))
    {
        uint64 limit = 1ul << (bits - 1); // the magnitude of the minimum
        double top = 1.0;
        for (var i = 1; i < bits; i += 1)
            top = top * 2.0;
        if (d >= top)
        {
            r.Mag = limit - 1;
            return r;
        }
        if (d <= -top)
        {
            r.Neg = true;
            r.Mag = limit;
            return r;
        }
        int64 n = (int64)d; // truncates toward zero
        r.Neg = n < 0;
        r.Mag = n < 0 ? unchecked((uint64)(-(n + 1))) + 1ul : (uint64)n;
        return r;
    }
    double topUnsigned = 1.0;
    for (var i = 0; i < bits; i += 1)
        topUnsigned = topUnsigned * 2.0;
    if (d >= topUnsigned)
    {
        r.Mag = ConstMask(bits);
        return r;
    }
    if (d <= 0.0)
        return r;
    r.Mag = (uint64)d;
    return r;
}

// ---------------------------------------------------------------------------
// Conversions
// ---------------------------------------------------------------------------

// A probe for ConversionCost: the type and the literal information of a constant.
Value ConstProbe(ConstVal v)
{
    var p = Value { Type = v.Type, HasLit = v.HasLit, LitIsFloat = v.Kind == ConstKind.Float, LitFloat = v.F };
    if (v.HasLit && v.Kind == ConstKind.Int)
        p.LitInt = v.Neg ? -(int64)v.Mag : (int64)v.Mag; // a literal is at most int64.MaxValue
    return p;
}

ConstVal ConstNumericConvert(const ref Compiler cg, ConstVal v, int to)
{
    var types = cg.Types;
    int from = v.Type;
    if (ConstIntLike(cg, from) && ConstIntLike(cg, to))
        return ConstFromPattern(cg, to, ConstPattern(v, 64));
    if (ConstIntLike(cg, from) && types.IsFloat(to))
        return ConstMakeFloat(cg, to, ConstToFloat(cg, v, to), false);
    if (types.IsFloat(from) && ConstIntLike(cg, to))
        return ConstSaturate(cg, v.F, to);
    if (types.IsFloat(from) && types.IsFloat(to))
        return ConstMakeFloat(cg, to, v.F, false);
    Fail(cg, SourceLoc { }, "internal error: invalid numeric conversion");
    return v;
}

// An unsuffixed literal takes the type of the value it is combined with, if it fits.
ConstVal ConstAdaptLiteral(const ref Compiler cg, ConstVal v, int to)
{
    var types = cg.Types;
    if (!v.HasLit)
        return v;
    if (v.Kind == ConstKind.Int)
    {
        bool fits = types.IsChar(to) ? ((!v.Neg || v.Mag == 0) && v.Mag <= 255ul) : (types.IsInt(to) && ConstFits(cg, v, to));
        if (fits)
            return ConstMakeInt(to, v.Neg, v.Mag, false);
    }
    if (types.IsFloat(to))
        return ConstMakeFloat(cg, to, v.Kind == ConstKind.Float ? v.F : ConstToFloat(cg, v, to), false);
    return v;
}

// The implicit conversion of a value to a type (the counterpart of ConvertValue).
ConstVal ConstUnknown(const ref Compiler cg)
{
    return ConstVal { Kind = ConstKind.Unknown, Type = cg.Types.Unknown };
}

// An error in a constant expression: Recover, and the value is unknown.
ConstVal ConstError(const ref Compiler cg, SourceLoc loc, string message)
{
    Recover(cg, loc, message);
    return ConstUnknown(cg);
}

ConstVal ConstConvert(const ref Compiler cg, ConstVal v, int to, SourceLoc loc, bool allowEnumInt)
{
    var types = cg.Types;
    if (v.Kind == ConstKind.Unknown || types.IsUnknown(to))
        return ConstUnknown(cg);
    int from = v.Type;
    if (from == to)
        return v;
    if (v.Kind == ConstKind.Slice)
        return ConstConvertSlice(cg, v, to, loc);
    // enumerators of imported C enums are written as integers
    if (allowEnumInt && types.IsEnum(to) && v.Kind == ConstKind.Int && !types.IsEnum(from))
    {
        if (!ConstFits(cg, v, types.Elem(to)))
            return ConstError(cg, loc, "enum value " + ConstDecimal(v) + " does not fit into " + types.Name(types.Elem(to)));
        return ConstFromPattern(cg, to, ConstPattern(v, 64));
    }
    if (ConversionCost(cg, ConstProbe(v), to) < 0)
    {
        string hint = "";
        if (types.IsNumeric(from) && types.IsNumeric(to))
            hint = " (an explicit cast is required)";
        return ConstError(cg, loc, "cannot implicitly convert '" + types.Name(from) + "' to '" + types.Name(to) + "'" + hint);
    }
    if (v.HasLit)
    {
        ConstVal a = ConstAdaptLiteral(cg, v, to);
        if (a.Type == to)
            return a;
    }
    if (types.IsNumeric(from) && types.IsNumeric(to))
        return ConstNumericConvert(cg, v, to);
    return ConstError(cg, loc, "cannot implicitly convert '" + types.Name(from) + "' to '" + types.Name(to) + "'");
    return v;
}

// The text of a float the way the program formats it at run time (RoundTripHelper in Runtime.csh): the fewest digits
// that read back as the same value. Written out here instead of using ToString() so that it does not depend on the
// compiler that built cshc.
string RoundTripText(double value, bool single)
{
    unsafe
    {
        char* buffer = (char*)Memory.Allocate(48);
        string result = "";
        int last = single ? 9 : 17;
        for (var p = single ? 6 : 15; p <= last; p += 1)
        {
            snprintf(buffer, 48, "%.*g".CStr(), p, value);
            result = string.FromCStr(buffer);
            double back = strtod(buffer, null);
            if (single ? (float)back == (float)value : back == value)
                break;
        }
        Memory.Free(buffer);
        return result;
    }
}

// The text of a value in a string concatenation.
string ConstToText(const ref Compiler cg, ConstVal v)
{
    switch (v.Kind)
    {
    case ConstKind.Unknown:
        return "?";
    case ConstKind.String:
        return v.S;
    case ConstKind.Bool:
        return v.B ? "true" : "false";
    case ConstKind.Float:
    {
        return RoundTripText(v.F, cg.Types.Bits(v.Type) == 32);
    }
    default:
    {
        if (cg.Types.IsChar(v.Type))
        {
            char c = (char)v.Mag;
            return c.ToString();
        }
        string number = ConstDecimal(v);
        if (cg.Types.IsEnum(v.Type))
        {
            // the member's name, like the text at run time (EnumTextFunction)
            var info = GetEnumInfo(cg, v.Type);
            for (var i = 0; i < info.Values.Length; i += 1)
            {
                if (info.Values[i].ToString() == number || unchecked((uint64)info.Values[i]).ToString() == number)
                    return info.Names[i];
            }
        }
        return number;
    }
    }
}

// The value as an IR constant.
Value ConstToValue(const ref Compiler cg, ConstVal v)
{
    var types = cg.Types;
    Value r;
    switch (v.Kind)
    {
    case ConstKind.Unknown:
        return Rvalue(types.Unknown, "", false);
    case ConstKind.Int:
        r = ConstInt(cg, v.Type, (int64)ConstPattern(v, 64));
        break;
    case ConstKind.Float:
        r = Rvalue(v.Type, FloatConstant(cg, v.Type, v.F), false);
        break;
    case ConstKind.Bool:
        r = MakeBool(cg, v.B ? "true" : "false");
        break;
    case ConstKind.Slice:
        return ConstSliceValue(cg, v);
    default:
        r = Rvalue(types.String, cg.Ir.StringLiteral(v.S), false);
        break;
    }
    if (v.HasLit)
    {
        r.HasLit = true;
        r.LitIsFloat = v.Kind == ConstKind.Float;
        r.LitFloat = v.F;
        if (v.Kind == ConstKind.Int)
            r.LitInt = v.Neg ? -(int64)v.Mag : (int64)v.Mag;
    }
    return r;
}

// A constant slice at run time: a view of a static block (not owned; the block is never freed).
Value ConstSliceValue(const ref Compiler cg, ConstVal v)
{
    var types = cg.Types;
    var ir = cg.Ir;
    if (!types.IsReadOnlySlice(v.Type))
        Fail(cg, SourceLoc { }, "internal error: a constant slice without a type");
    int elem = types.Elem(v.Type);
    string elemIr = LlvmType(cg, elem);
    var items = new string[v.Items.Length];
    for (var i = 0; i < items.Length; i += 1)
        items[i] = elemIr + " " + ConstToValue(cg, v.Items[i]).V;
    string block = ir.ConstArrayBlock(elemIr, items);
    string ty = LlvmType(cg, v.Type);
    string agg = ir.InsertValue(ty, "zeroinitializer", "ptr", block, "0");
    agg = ir.InsertValue(ty, agg, "ptr", DataPtr(cg, block), "1");
    agg = ir.InsertValue(ty, agg, SizeIr(cg), items.Length.ToString(), "2");
    return Rvalue(v.Type, agg, false);
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

ConstVal ConstOverflow(const ref Compiler cg, SourceLoc loc, int t)
{
    return ConstError(cg, loc, "integer overflow in a constant expression (the value does not fit into " + cg.Types.Name(t) + ")");
}

ConstVal ConstIntOp(const ref Compiler cg, BinOp op, ConstVal l, ConstVal r, int t, SourceLoc loc)
{
    var result = ConstVal { Kind = ConstKind.Int, Type = t };
    int bits = cg.Types.Bits(t);
    bool sgn = ConstSignedType(cg, t);
    switch (op)
    {
    case BinOp.Add:
    case BinOp.Sub:
    case BinOp.Mul:
    {
        bool ok;
        if (op == BinOp.Mul)
        {
            ok = l.Mag == 0 || r.Mag <= 0xFFFFFFFFFFFFFFFFul / l.Mag;
            result.Mag = unchecked(l.Mag * r.Mag);
            result.Neg = (l.Neg != r.Neg) && result.Mag != 0;
        }
        else
        {
            var sum = ConstAddSigned(l.Neg, l.Mag, op == BinOp.Add ? r.Neg : !r.Neg, r.Mag);
            ok = sum.Ok;
            result.Neg = sum.Neg;
            result.Mag = sum.Mag;
        }
        if (!ok || !ConstFits(cg, result, t))
            return ConstOverflow(cg, loc, t);
        return result;
    }
    case BinOp.Div:
    case BinOp.Rem:
    {
        if (r.Mag == 0)
            return ConstError(cg, loc, "division by zero in constant expression");
        if (sgn && l.Neg && l.Mag == (1ul << (bits - 1)) && r.Neg && r.Mag == 1)
            return ConstOverflow(cg, loc, t); // the smallest value divided by -1
        uint64 q = l.Mag / r.Mag;
        uint64 rem = l.Mag % r.Mag;
        if (op == BinOp.Div)
        {
            result.Neg = (l.Neg != r.Neg) && q != 0;
            result.Mag = q;
        }
        else
        {
            result.Neg = l.Neg && rem != 0;
            result.Mag = rem;
        }
        return result;
    }
    case BinOp.BitAnd:
    {
        return ConstFromPattern(cg, t, ConstPattern(l, bits) & ConstPattern(r, bits));
    }
    case BinOp.BitOr:
    {
        return ConstFromPattern(cg, t, ConstPattern(l, bits) | ConstPattern(r, bits));
    }
    case BinOp.BitXor:
    {
        return ConstFromPattern(cg, t, ConstPattern(l, bits) ^ ConstPattern(r, bits));
    }
    case BinOp.Shl:
    case BinOp.Shr:
    {
        uint64 a = ConstPattern(l, bits);
        int count = (int)(ConstPattern(r, 64) & (uint64)(bits - 1));
        uint64 res;
        if (op == BinOp.Shl)
            res = a << count;
        else if (sgn && ((a >> (bits - 1)) & 1ul) == 1ul)
            res = ~((~a & ConstMask(bits)) >> count); // arithmetic shift of a negative value
        else
            res = a >> count;
        return ConstFromPattern(cg, t, res);
    }
    default:
        break;
    }
    Fail(cg, SourceLoc { }, "internal error: invalid integer operation");
    return result;
}

ConstVal ConstArith(const ref Compiler cg, BinOp op, ConstVal l0, ConstVal r0, SourceLoc loc)
{
    var types = cg.Types;
    var l = l0;
    var r = r0;

    if (l.Kind == ConstKind.Slice || r.Kind == ConstKind.Slice)
        return ConstError(cg, loc, "operator '" + BinOpText(op) + "' cannot be applied to '" + types.Name(l.Type) + "' and '" + types.Name(r.Type) + "'");

    // String concatenation (the other operand may be any primitive).
    if (op == BinOp.Add && (types.IsString(l.Type) || types.IsString(r.Type)))
        return ConstVal { Kind = ConstKind.String, Type = types.String, S = ConstToText(cg, l) + ConstToText(cg, r) };

    // Bit operations on enums and bools.
    if (l.Type == r.Type && (op == BinOp.BitAnd || op == BinOp.BitOr || op == BinOp.BitXor))
    {
        if (types.IsBool(l.Type))
        {
            bool value = op == BinOp.BitAnd ? (l.B && r.B) : (op == BinOp.BitOr ? (l.B || r.B) : l.B != r.B);
            return ConstMakeBool(cg, value);
        }
        if (types.IsEnum(l.Type))
            return ConstIntOp(cg, op, l, r, l.Type, loc);
    }

    if (!types.IsNumeric(l.Type) || !types.IsNumeric(r.Type))
        return ConstError(cg, loc, "operator '" + BinOpText(op) + "' cannot be applied to '" + types.Name(l.Type) + "' and '" + types.Name(r.Type) + "'");

    // Shifts: the result has the (promoted) type of the left operand.
    if (op == BinOp.Shl || op == BinOp.Shr)
    {
        if (!types.IsIntegral(l.Type) || !types.IsIntegral(r.Type))
            return ConstError(cg, loc, "shift operators require integer operands");
        int st = PromoteTypes(cg, l.Type, l.Type, loc);
        ConstVal lv = ConstConvert(cg, l.HasLit ? ConstAdaptLiteral(cg, l, st) : l, st, loc, false);
        return ConstIntOp(cg, op, lv, r, st, loc);
    }

    // Adapt literals to the other operand's type.
    if (l.HasLit && !r.HasLit)
        l = ConstAdaptLiteral(cg, l, r.Type);
    else if (r.HasLit && !l.HasLit)
        r = ConstAdaptLiteral(cg, r, l.Type);

    int t = PromoteTypes(cg, l.Type, r.Type, loc);
    ConstVal lc = ConstConvert(cg, l, t, loc, false);
    ConstVal rc = ConstConvert(cg, r, t, loc, false);

    if (types.IsFloat(t))
    {
        double res = 0.0;
        switch (op)
        {
        case BinOp.Add:
            res = lc.F + rc.F;
            break;
        case BinOp.Sub:
            res = lc.F - rc.F;
            break;
        case BinOp.Mul:
            res = lc.F * rc.F;
            break;
        case BinOp.Div:
            res = lc.F / rc.F;
            break;
        case BinOp.Rem:
            res = lc.F % rc.F;
            break;
        default:
            return ConstError(cg, loc, "bit operations are not defined for floating point values");
            break;
        }
        return ConstMakeFloat(cg, t, res, false);
    }
    return ConstIntOp(cg, op, lc, rc, t, loc);
}

ConstVal ConstDecide(const ref Compiler cg, BinOp op, int order)
{
    switch (op)
    {
    case BinOp.Eq: return ConstMakeBool(cg, order == 0);
    case BinOp.Ne: return ConstMakeBool(cg, order != 0);
    case BinOp.Lt: return ConstMakeBool(cg, order == -1);
    case BinOp.Gt: return ConstMakeBool(cg, order == 1);
    case BinOp.Le: return ConstMakeBool(cg, order == -1 || order == 0);
    default: return ConstMakeBool(cg, order == 1 || order == 0);
    }
}

ConstVal ConstCompare(const ref Compiler cg, BinOp op, ConstVal l0, ConstVal r0, SourceLoc loc)
{
    var types = cg.Types;
    var l = l0;
    var r = r0;
    bool isEq = op == BinOp.Eq || op == BinOp.Ne;

    if (types.IsString(l.Type) && types.IsString(r.Type))
    {
        if (!isEq)
            return ConstError(cg, loc, "strings can only be compared with '==' and '!='");
        return ConstMakeBool(cg, (l.S == r.S) == (op == BinOp.Eq));
    }

    if (l.HasLit && !r.HasLit)
        l = ConstAdaptLiteral(cg, l, r.Type);
    else if (r.HasLit && !l.HasLit)
        r = ConstAdaptLiteral(cg, r, l.Type);

    // Bool and enum.
    if (l.Type == r.Type && (types.IsBool(l.Type) || types.IsEnum(l.Type)))
    {
        if (types.IsBool(l.Type))
        {
            if (!isEq)
                return ConstError(cg, loc, "bool values can only be compared with '==' and '!='");
            return ConstMakeBool(cg, (l.B == r.B) == (op == BinOp.Eq));
        }
        return ConstDecide(cg, op, ConstOrder(l, r));
    }

    if (!types.IsNumeric(l.Type) || !types.IsNumeric(r.Type))
        return ConstError(cg, loc, "cannot compare '" + types.Name(l.Type) + "' with '" + types.Name(r.Type) + "'");

    int t = PromoteTypes(cg, l.Type, r.Type, loc);
    ConstVal lc = ConstConvert(cg, l, t, loc, false);
    ConstVal rc = ConstConvert(cg, r, t, loc, false);
    if (types.IsFloat(t))
    {
        if (lc.F != lc.F || rc.F != rc.F)
            return ConstMakeBool(cg, op == BinOp.Ne); // only != is true for unordered values
        return ConstDecide(cg, op, lc.F < rc.F ? -1 : (lc.F > rc.F ? 1 : 0));
    }
    return ConstDecide(cg, op, ConstOrder(lc, rc));
}

// ---------------------------------------------------------------------------
// The evaluator
// ---------------------------------------------------------------------------

bool IsConstantType(const ref Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsUnknown(t))
        return true; // reported where the type is written
    if (types.IsReadOnlySlice(t))
        return IsConstantElementType(cg, types.Elem(t));
    return IsConstantElementType(cg, t);
}

bool IsConstantElementType(const ref Compiler cg, int t)
{
    var types = cg.Types;
    return types.IsNumeric(t) || types.IsBool(t) || types.IsString(t) || types.IsEnum(t);
}

// The error for a constant of a type that cannot be constant (arrays and slices get a hint); the type is unknown then.
int RecoverConstantType(const ref Compiler cg, SourceLoc loc, int t)
{
    var types = cg.Types;
    if ((types.IsArray(t) || types.Kind(t) == TypeKind.Slice) && IsConstantElementType(cg, types.Elem(t)))
        return RecoverType(cg, loc, "a constant cannot be '" + types.Name(t) + "' (its elements could be changed); use 'const ReadOnlySlice<" +
                      types.Name(types.Elem(t)) + ">'");
    return RecoverType(cg, loc, "constants can only be numbers, bool, char, string, enum values or a ReadOnlySlice<T> of them");
}

ConstVal ConstNotConstant(const ref Compiler cg, ConstScope sc)
{
    Recover(cg, sc.DeclLoc, "the initializer of " + sc.What + " must be a constant expression (literals, operators, other constants)");
    return ConstUnknown(cg);
}

ConstVal ConstEval(const ref Compiler cg, Expr e, ConstScope sc)
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
            return ConstMakeInt(t, false, l.Value, false);
        }
        if (l.Value <= 0x7FFFFFFFul)
            return ConstMakeInt(types.I32, false, l.Value, true);
        if (l.Value <= 0x7FFFFFFFFFFFFFFFul)
            return ConstMakeInt(types.I64, false, l.Value, true);
        return ConstMakeInt(types.U64, false, l.Value, false);
    }
    case ExprKind.FloatLit:
    {
        var l = tree.GetFloatLit(e);
        if (l.IsFloat32)
            return ConstMakeFloat(cg, types.F32, l.Value, false);
        return ConstMakeFloat(cg, types.F64, l.Value, true);
    }
    case ExprKind.CharLit:
        return ConstMakeInt(types.Char, false, (uint64)tree.GetCharLit(e).Value, false);
    case ExprKind.StringLit:
        return ConstVal { Kind = ConstKind.String, Type = types.String, S = tree.GetStringLit(e).Value };
    case ExprKind.Embed:
    case ExprKind.EmbedFilenames:
    case ExprKind.EmbedLines:
        FailEmbedPlace(cg, e.Loc);
        break;
    case ExprKind.BoolLit:
        return ConstMakeBool(cg, tree.GetBoolLit(e).Value);
    case ExprKind.Name:
    {
        string name = tree.GetName(e).Name;
        if (sc.HasEnum)
        {
            // an earlier member of the enum that is being declared
            int member = FindEnumMember(sc.Enum, name);
            if (member >= 0)
                return ConstFromPattern(cg, sc.Enum.Base, (uint64)sc.Enum.Values[member]);
        }
        if (sc.Locals)
        {
            int local = FindLocal(cg, name);
            if (local >= 0)
            {
                var variable = cg.Fn[0].Vars.Get(local);
                if (!variable.IsConstant)
                    return ConstNotConstant(cg, sc); // a local variable hides a constant of the same name
                return variable.ConstValue;
            }
        }
        int c = LookupConst(cg, sc.File, name);
        if (c >= 0)
            return ConstEvalDecl(cg, c);
        return ConstNotConstant(cg, sc);
    }
    case ExprKind.Member:
    {
        // Ns.Constant or Enum.Member
        var m = tree.GetMember(e);
        int metaEnum = EnumMetaType(cg, m.Object, sc.File, sc.Env);
        if (metaEnum != 0)
            return EnumMeta(cg, metaEnum, m.Name, e.Loc);
        string dotted = DottedName(cg, m.Object);
        if (dotted.Length == 0)
        {
            if (m.Name == "Length")
                return ConstLength(cg, ConstEval(cg, m.Object, sc), e.Loc);
            return ConstNotConstant(cg, sc);
        }
        if (sc.Locals && FindLocal(cg, dotted.Split('.')[0].ToString()) >= 0)
            return ConstNotConstant(cg, sc);
        int c = LookupConst(cg, sc.File, dotted + "." + m.Name);
        if (c >= 0)
            return ConstEvalDecl(cg, c);
        var entry = TypeDeclEntry { };
        if (LookupTypeDecl(cg, sc.File, dotted, ref entry) && entry.Kind == DeclKind.Enum)
        {
            int et = GetEnumType(cg, entry.Index);
            var info = GetEnumInfo(cg, et);
            int member = FindEnumMember(info, m.Name);
            if (member < 0)
                return ConstError(cg, e.Loc, "enum '" + types.Name(et) + "' has no member '" + m.Name + "'");
            return ConstFromPattern(cg, et, (uint64)info.Values[member]);
        }
        if (m.Name == "Length")
            return ConstLength(cg, ConstEval(cg, m.Object, sc), e.Loc);
        return ConstNotConstant(cg, sc);
    }
    case ExprKind.Collection:
    {
        // [a, b, ..c]: its element type comes from the constant's type (ConstConvertSlice)
        var n = tree.GetCollection(e);
        var items = List<ConstVal>.Create();
        for (var i = 0; i < n.Items.Length; i += 1)
        {
            ConstVal item = ConstEval(cg, n.Items[i], sc);
            if (item.Kind == ConstKind.Unknown)
                return item;
            if (!n.Spread[i])
            {
                if (item.Kind == ConstKind.Slice)
                    return ConstError(cg, n.Items[i].Loc, "a constant slice cannot contain slices");
                items.Add(item);
                continue;
            }
            if (item.Kind != ConstKind.Slice)
                return ConstError(cg, n.Items[i].Loc, "'..' in a constant spreads a constant slice, not '" + types.Name(item.Type) + "'");
            items.AddRange(item.Items);
        }
        return ConstVal { Kind = ConstKind.Slice, Type = types.Collection, Items = items.ToArray() };
    }
    case ExprKind.Index:
    {
        var ix = tree.GetIndex(e);
        ConstVal obj = ConstEval(cg, ix.Object, sc);
        if (obj.Kind == ConstKind.Unknown)
            return obj;
        if (obj.Kind != ConstKind.Slice)
            return ConstNotConstant(cg, sc);
        ConstVal index = ConstEval(cg, ix.Index, sc);
        if (index.Kind == ConstKind.Unknown)
            return index;
        int i = ConstIndex(cg, index, ix.FromEnd, obj.Items.Length, ix.Index.Loc);
        if (i == ConstBadIndex())
            return ConstUnknown(cg);
        if (i < 0 || i >= obj.Items.Length)
            return ConstError(cg, e.Loc, "index " + i.ToString() + " is out of range (the constant slice has " + obj.Items.Length.ToString() + " elements)");
        return obj.Items[i];
    }
    case ExprKind.Slice:
    {
        var n = tree.GetSlice(e);
        ConstVal obj = ConstEval(cg, n.Object, sc);
        if (obj.Kind == ConstKind.Unknown)
            return obj;
        if (obj.Kind != ConstKind.Slice)
            return ConstNotConstant(cg, sc);
        int length = obj.Items.Length;
        ConstVal startValue = n.Start.IsNull() ? ConstMakeInt(types.I32, false, 0ul, false) : ConstEval(cg, n.Start, sc);
        ConstVal endValue = n.End.IsNull() ? ConstMakeInt(types.I32, false, (uint64)length, false) : ConstEval(cg, n.End, sc);
        if (startValue.Kind == ConstKind.Unknown || endValue.Kind == ConstKind.Unknown)
            return ConstUnknown(cg);
        int start = n.Start.IsNull() ? 0 : ConstIndex(cg, startValue, n.StartFromEnd, length, n.Start.Loc);
        int end = n.End.IsNull() ? length : ConstIndex(cg, endValue, n.EndFromEnd, length, n.End.Loc);
        if (start == ConstBadIndex() || end == ConstBadIndex())
            return ConstUnknown(cg);
        if (start < 0 || start > end || end > length)
            return ConstError(cg, e.Loc, "slice range " + start.ToString() + ".." + end.ToString() + " is out of bounds (the constant slice has " +
                            length.ToString() + " elements)");
        var part = new ConstVal[end - start];
        for (var i = start; i < end; i += 1)
            part[i - start] = obj.Items[i];
        return ConstVal { Kind = ConstKind.Slice, Type = obj.Type, Items = part };
    }
    case ExprKind.Unary:
    {
        var u = tree.GetUnary(e);
        if (u.Op == UnOp.Deref || u.Op == UnOp.AddrOf)
            return ConstNotConstant(cg, sc);
        ConstVal v = ConstEval(cg, u.Operand, sc);
        if (v.Kind == ConstKind.Unknown)
            return v;
        switch (u.Op)
        {
        case UnOp.Neg:
        case UnOp.Plus:
        {
            if (v.HasLit && u.Op == UnOp.Neg)
            {
                if (v.Kind == ConstKind.Float)
                {
                    v.F = -v.F;
                    return v;
                }
                // -n of an integer literal: int32 if it fits, otherwise int64
                bool neg = !v.Neg && v.Mag != 0;
                bool fits32 = neg ? v.Mag <= (1ul << 31) : v.Mag < (1ul << 31);
                return ConstMakeInt(fits32 ? types.I32 : types.I64, neg, v.Mag, true);
            }
            if (!types.IsNumeric(v.Type))
                return ConstError(cg, e.Loc, "unary '-' cannot be applied to '" + types.Name(v.Type) + "'");
            int t = types.IsFloat(v.Type) ? v.Type : PromoteTypes(cg, v.Type, v.Type, e.Loc);
            ConstVal c = ConstConvert(cg, v, t, e.Loc, false);
            if (u.Op == UnOp.Plus)
                return c;
            if (types.IsFloat(t))
                return ConstMakeFloat(cg, t, -c.F, false);
            if (!types.IsSigned(t))
                return ConstError(cg, e.Loc, "unary '-' cannot be applied to unsigned type '" + types.Name(t) + "'");
            return ConstIntOp(cg, BinOp.Sub, ConstMakeInt(t, false, 0ul, false), c, t, e.Loc);
        }
        case UnOp.Not:
        {
            if (types.IsBool(v.Type))
                return ConstMakeBool(cg, !v.B);
            return ConstError(cg, e.Loc, "operator '!' cannot be applied to '" + types.Name(v.Type) + "'");
            return v;
        }
        case UnOp.BitNot:
        {
            if (types.IsEnum(v.Type))
                return ConstFromPattern(cg, v.Type, ~ConstPattern(v, types.Bits(v.Type)));
            if (!types.IsIntegral(v.Type))
                return ConstError(cg, e.Loc, "operator '~' cannot be applied to '" + types.Name(v.Type) + "'");
            int t = PromoteTypes(cg, v.Type, v.Type, e.Loc);
            ConstVal c = ConstConvert(cg, v, t, e.Loc, false);
            return ConstFromPattern(cg, t, ~ConstPattern(c, types.Bits(t)));
        }
        default:
            break;
        }
        return ConstNotConstant(cg, sc);
    }
    case ExprKind.Binary:
    {
        var b = tree.GetBinary(e);
        if (b.Op == BinOp.LogAnd || b.Op == BinOp.LogOr)
        {
            // the right side is only evaluated if it can change the result
            ConstVal l = ConstEval(cg, b.Lhs, sc);
            if (l.Kind == ConstKind.Unknown)
                return l;
            if (!types.IsBool(l.Type))
                return ConstError(cg, b.Lhs.Loc, "a condition must be of type 'bool', not '" + types.Name(l.Type) + "' (there is no implicit conversion to bool)");
            if (b.Op == BinOp.LogAnd ? !l.B : l.B)
                return l;
            ConstVal r = ConstEval(cg, b.Rhs, sc);
            if (r.Kind == ConstKind.Unknown)
                return r;
            if (!types.IsBool(r.Type))
                return ConstError(cg, b.Rhs.Loc, "a condition must be of type 'bool', not '" + types.Name(r.Type) + "' (there is no implicit conversion to bool)");
            return r;
        }
        ConstVal lhs = ConstEval(cg, b.Lhs, sc);
        ConstVal rhs = ConstEval(cg, b.Rhs, sc);
        if (lhs.Kind == ConstKind.Unknown || rhs.Kind == ConstKind.Unknown)
            return ConstUnknown(cg);
        switch (b.Op)
        {
        case BinOp.Eq:
        case BinOp.Ne:
        case BinOp.Lt:
        case BinOp.Gt:
        case BinOp.Le:
        case BinOp.Ge:
            return ConstCompare(cg, b.Op, lhs, rhs, e.Loc);
        default:
            return ConstArith(cg, b.Op, lhs, rhs, e.Loc);
        }
    }
    case ExprKind.Cast:
    {
        var c = tree.GetCast(e);
        int to = ResolveValueType(cg, c.Type.Id, sc.File, sc.Env);
        ConstVal v = ConstEval(cg, c.Operand, sc);
        if (v.Kind == ConstKind.Unknown || types.IsUnknown(to))
            return ConstUnknown(cg);
        int from = v.Type;
        if (from == to)
            return v;
        if (ConversionCost(cg, ConstProbe(v), to) >= 0)
            return ConstConvert(cg, v, to, e.Loc, false);
        bool fromNumeric = types.IsInt(from) || types.IsChar(from) || types.IsEnum(from) || types.IsFloat(from);
        bool toNumeric = types.IsInt(to) || types.IsChar(to) || types.IsEnum(to) || types.IsFloat(to);
        if (fromNumeric && toNumeric)
        {
            if (types.IsEnum(from) && types.IsFloat(to))
                return ConstError(cg, e.Loc, "cannot cast an enum to a floating point type");
            return ConstNumericConvert(cg, v, to);
        }
        return ConstError(cg, e.Loc, "cannot cast '" + types.Name(from) + "' to '" + types.Name(to) + "'");
        return v;
    }
    case ExprKind.SizeOf:
    {
        int t = ResolveValueType(cg, tree.GetSizeOf(e).Type.Id, sc.File, sc.Env);
        if (types.IsUnknown(t))
            return ConstUnknown(cg);
        if (types.IsVoid(t))
            return ConstError(cg, e.Loc, "sizeof(void) is not defined");
        return ConstMakeInt(types.I32, false, (uint64)TypeLayout(cg, t).Size, false);
    }
    default:
        break;
    }
    return ConstNotConstant(cg, sc);
}

// ---------------------------------------------------------------------------
// Constant slices and Enum<T>
// ---------------------------------------------------------------------------

// The index of ConstIndex after an error (reported): the result is unknown.
int ConstBadIndex()
{
    return -2147483647;
}

// An index or a range bound of a constant slice (^n counts from the end). Values that do not fit are reported as -1.
int ConstIndex(const ref Compiler cg, ConstVal v, bool fromEnd, int length, SourceLoc loc)
{
    var types = cg.Types;
    if (v.Kind != ConstKind.Int || !types.IsIntegral(v.Type) || types.IsEnum(v.Type))
    {
        Recover(cg, loc, "an index must be an integer, not '" + types.Name(v.Type) + "'");
        return ConstBadIndex();
    }
    if (v.Mag > 0x7FFFFFFFul)
        return -1;
    int i = v.Neg ? -(int)v.Mag : (int)v.Mag;
    return fromEnd ? length - i : i;
}

// x.Length of a constant slice or string.
ConstVal ConstLength(const ref Compiler cg, ConstVal v, SourceLoc loc)
{
    var types = cg.Types;
    if (v.Kind == ConstKind.Unknown)
        return v;
    if (v.Kind == ConstKind.Slice)
        return ConstMakeInt(types.I32, false, (uint64)v.Items.Length, false);
    if (v.Kind == ConstKind.String)
        return ConstMakeInt(types.I32, false, (uint64)v.S.Length, false);
    return ConstError(cg, loc, "'" + types.Name(v.Type) + "' has no member 'Length'");
    return v;
}

// A collection or constant slice as ReadOnlySlice<T>: every element converts to T.
ConstVal ConstConvertSlice(const ref Compiler cg, ConstVal v, int to, SourceLoc loc)
{
    var types = cg.Types;
    if (!types.IsReadOnlySlice(to) || (v.Type != types.Collection && types.Elem(v.Type) != types.Elem(to)))
    {
        string hint = types.IsArray(to) || types.Kind(to) == TypeKind.Slice ? " (a constant slice is read-only; copy it with .ToArray())" : "";
        return ConstError(cg, loc, "cannot implicitly convert '" + types.Name(v.Type) + "' to '" + types.Name(to) + "'" + hint);
    }
    int elem = types.Elem(to);
    var items = new ConstVal[v.Items.Length];
    for (var i = 0; i < items.Length; i += 1)
        items[i] = ConstConvert(cg, v.Items[i], elem, loc, false);
    return ConstVal { Kind = ConstKind.Slice, Type = to, Items = items };
}

// The enum of Enum<T> (the object of Enum<T>.Count and so on; the unknown type in the checker's generic bodies), or 0
// if the expression is something else.
int EnumMetaType(const ref Compiler cg, Expr e, int file, Dictionary<string, int> env)
{
    if (e.Kind != ExprKind.Name)
        return 0;
    var n = cg.Tree.GetName(e);
    if (n.Name != "Enum" || n.TypeArgs.Length != 1)
        return 0;
    var entry = TypeDeclEntry { };
    if (LookupTypeDecl(cg, file, "Enum", ref entry))
        return 0; // a type of the program that is called Enum
    int t = ResolveValueType(cg, n.TypeArgs[0].Id, file, env);
    if (!cg.Types.IsEnum(t) && !cg.Types.IsUnknown(t)) // unknown: a generic body the checker checks once
        Fail(cg, e.Loc, "Enum<T> needs an enum type, not '" + cg.Types.Name(t) + "'");
    return t;
}

// Enum<T>.Count, .Min, .Max, .Values, .Names: facts about an enum, as constants.
ConstVal EnumMeta(const ref Compiler cg, int et, string what, SourceLoc loc)
{
    var types = cg.Types;
    if (types.IsUnknown(et))
        return ConstUnknown(cg);
    var info = GetEnumInfo(cg, et);
    int n = info.Values.Length;
    bool isSigned = ConstSignedType(cg, types.Elem(et));
    switch (what)
    {
    case "Count":
        return ConstMakeInt(types.I32, false, (uint64)n, false);
    case "Min":
    case "Max":
    {
        if (n == 0)
            return ConstError(cg, loc, "enum '" + types.Name(et) + "' has no members, so it has no " + what);
        int64 best = info.Values[0];
        for (var i = 1; i < n; i += 1)
        {
            int64 v = info.Values[i];
            bool less = isSigned ? v < best : unchecked((uint64)v) < unchecked((uint64)best);
            if (what == "Min" ? less : (!less && v != best))
                best = v;
        }
        return ConstFromPattern(cg, et, unchecked((uint64)best));
    }
    case "Values":
    {
        var items = new ConstVal[n];
        for (var i = 0; i < n; i += 1)
            items[i] = ConstFromPattern(cg, et, unchecked((uint64)info.Values[i]));
        return ConstVal { Kind = ConstKind.Slice, Type = types.ReadOnlySliceOf(et), Items = items };
    }
    case "Names":
    {
        var items = new ConstVal[n];
        for (var i = 0; i < n; i += 1)
            items[i] = ConstVal { Kind = ConstKind.String, Type = types.String, S = info.Names[i] };
        return ConstVal { Kind = ConstKind.Slice, Type = types.ReadOnlySliceOf(types.String), Items = items };
    }
    default:
        break;
    }
    return ConstError(cg, loc, "Enum<" + types.Name(et) + "> has no member '" + what + "' (only Count, Min, Max, Values and Names)");
    return ConstVal { };
}

// ---------------------------------------------------------------------------
// embed("file"), embed("*.txt"), embed_filenames("*.txt"), embed_lines("file")
// ---------------------------------------------------------------------------

bool IsEmbedExpr(Expr e)
{
    return e.Kind == ExprKind.Embed || e.Kind == ExprKind.EmbedFilenames || e.Kind == ExprKind.EmbedLines;
}

void FailEmbedPlace(const ref Compiler cg, SourceLoc loc)
{
    Fail(cg, loc, EmbedPlaceError());
}

string EmbedPlaceError()
{
    return "embed(...), embed_filenames(...) and embed_lines(...) can only be the whole initializer of a constant: " +
           "const string Text = embed(\"file.txt\"); const ReadOnlySlice<string> Texts = embed(\"*.txt\");";
}

// True if the name has a wildcard ('*': any characters, '?': one character).
bool HasWildcard(string name)
{
    return name.IndexOf('*') >= 0 || name.IndexOf('?') >= 0;
}

// True if 'name' matches the pattern with '*' and '?'.
bool WildcardMatch(string pattern, string name)
{
    int p = 0;
    int n = 0;
    int starP = -1; // the last '*' seen and where in the name it started
    int starN = 0;
    while (n < name.Length)
    {
        if (p < pattern.Length && (pattern[p] == '?' || pattern[p] == name[n]))
        {
            p += 1;
            n += 1;
        }
        else if (p < pattern.Length && pattern[p] == '*')
        {
            starP = p;
            starN = n;
            p += 1;
        }
        else if (starP >= 0)
        {
            // let the last '*' take one more character
            p = starP + 1;
            starN += 1;
            n = starN;
        }
        else
            return false;
    }
    while (p < pattern.Length && pattern[p] == '*')
        p += 1;
    return p == pattern.Length;
}

// The folders a relative embed path is looked up in: the folder of the source file, then the project folder.
List<string> EmbedBases(const ref Compiler cg, SourceLoc loc)
{
    var bases = List<string>.Create();
    bases.Add(Path.GetDirectory(cg.Diag.Files.Get(loc.File)));
    string projectDir = cg.St[0].ProjectDir;
    if (projectDir.Length > 0)
        bases.Add(projectDir);
    return bases;
}

// The file of embed("name"): an absolute path as it is, otherwise relative to the source file that uses it, then
// relative to the project's folder.
string EmbedPath(const ref Compiler cg, string word, string name, SourceLoc loc)
{
    if (Path.IsRooted(name))
    {
        if (!File.Exists(name) || Directory.Exists(name))
            Fail(cg, loc, word + ": the file '" + name + "' does not exist");
        return name;
    }
    string tried = "";
    foreach (var baseDir in EmbedBases(cg, loc))
    {
        string path = Path.Combine(baseDir, name);
        if (File.Exists(path) && !Directory.Exists(path))
            return path;
        tried += (tried.Length > 0 ? " and '" : "'") + path + "'";
    }
    Fail(cg, loc, word + ": cannot find the file '" + name + "' (looked for " + tried + ")");
    return "";
}

// The files of embed("dir/*.txt"): the wildcards may only be in the file name. The folder is looked up like a file
// (absolute, beside the source file, in the project folder); the first folder with a matching file is used. The
// names are sorted; no match gives an empty list.
List<string> EmbedMatches(const ref Compiler cg, string word, string pattern, SourceLoc loc, ref string folder)
{
    string dir = Path.GetDirectory(pattern);
    string filePattern = Path.GetFileName(pattern);
    if (HasWildcard(dir))
        Fail(cg, loc, word + ": wildcards ('*', '?') are only allowed in the file name, not in the folder: '" + pattern + "'");
    var bases = List<string>.Create();
    if (Path.IsRooted(pattern))
        bases.Add("");
    else
        bases = EmbedBases(cg, loc);
    var names = List<string>.Create();
    foreach (var baseDir in bases)
    {
        string candidate = Path.Combine(baseDir, dir);
        if (candidate.Length == 0)
            candidate = ".";
        if (!Directory.Exists(candidate))
            continue;
        foreach (var entry in Directory.GetEntries(candidate))
        {
            if (WildcardMatch(filePattern, entry) && !Directory.Exists(Path.Combine(candidate, entry)))
                names.Add(entry);
        }
        if (names.Count() > 0)
        {
            folder = candidate;
            return names;
        }
    }
    return names;
}

string EmbedRead(const ref Compiler cg, string word, string path, SourceLoc loc)
{
    var read = File.ReadAllText(path); // UTF-8; a byte order mark is dropped, everything else stays as it is
    if (read is string text)
        return text;
    if (read is error e)
        Fail(cg, loc, word + ": cannot read '" + path + "': " + e.Message);
    return "";
}

// const string X = embed("file"): the content of the file, read now. Line ends, quotes and everything else stay as they
// are; only a byte order mark is dropped. The text must be UTF-8 like every string.
// const ReadOnlySlice<string> X = embed("dir/*.txt"): the contents of the matching files, sorted by name.
// embed_filenames gives the file names (without the folder) instead: a string without wildcards (the file must
// exist), a ReadOnlySlice<string> with them (in the same order as embed).
// const ReadOnlySlice<string> X = embed_lines("file"): the lines of one file (see EmbedLines).
ConstVal ConstEmbed(const ref Compiler cg, Expr init, int t)
{
    var types = cg.Types;
    bool wantNames = init.Kind == ExprKind.EmbedFilenames;
    string word = wantNames ? "embed_filenames" : "embed";
    string pattern = cg.Tree.GetEmbed(init).Value;
    if (init.Kind == ExprKind.EmbedLines)
        return ConstEmbedLines(cg, init, t, pattern);
    if (!HasWildcard(pattern))
    {
        if (!types.IsString(t))
            return ConstError(cg, init.Loc, word + "(\"" + pattern + "\") gives a string, so the constant must be 'const string', not '" + types.Name(t) +
                "' (a pattern with '*' or '?' gives a ReadOnlySlice<string>)");
        string path = EmbedPath(cg, word, pattern, init.Loc);
        string value = wantNames ? Path.GetFileName(path) : EmbedRead(cg, word, path, init.Loc);
        return ConstVal { Kind = ConstKind.String, Type = types.String, S = value };
    }
    int sliceType = types.ReadOnlySliceOf(types.String);
    if (t != sliceType)
        return ConstError(cg, init.Loc, word + "(\"" + pattern + "\") gives the files that match, so the constant must be 'const ReadOnlySlice<string>', not '" +
            types.Name(t) + "'");
    string folder = "";
    var names = EmbedMatches(cg, word, pattern, init.Loc, ref folder);
    var items = new ConstVal[names.Count()];
    for (var i = 0; i < items.Length; i += 1)
    {
        string value = wantNames ? names.Get(i) : EmbedRead(cg, word, Path.Combine(folder, names.Get(i)), init.Loc);
        items[i] = ConstVal { Kind = ConstKind.String, Type = types.String, S = value };
    }
    return ConstVal { Kind = ConstKind.Slice, Type = sliceType, Items = items };
}

// const ReadOnlySlice<string> X = embed_lines("file"): the lines of one file, read now, without their line ends (\n or
// \r\n); a line end at the end of the file does not start another line, and an empty file has no lines.
ConstVal ConstEmbedLines(const ref Compiler cg, Expr init, int t, string pattern)
{
    var types = cg.Types;
    if (HasWildcard(pattern))
        return ConstError(cg, init.Loc, "embed_lines reads one file, without '*' or '?' (the contents of several files: embed(\"" + pattern + "\"))");
    int sliceType = types.ReadOnlySliceOf(types.String);
    if (t != sliceType)
        return ConstError(cg, init.Loc, "embed_lines(\"" + pattern + "\") gives the lines of the file, so the constant must be 'const ReadOnlySlice<string>', not '" +
            types.Name(t) + "'");
    string text = EmbedRead(cg, "embed_lines", EmbedPath(cg, "embed_lines", pattern, init.Loc), init.Loc);
    var lines = List<ConstVal>.Create();
    int start = 0;
    while (start < text.Length)
    {
        int end = text.IndexOf('\n', start);
        int next = end + 1;
        if (end < 0)
        {
            end = text.Length;
            next = end;
        }
        int stop = end > start && text[end - 1] == '\r' ? end - 1 : end;
        lines.Add(ConstVal { Kind = ConstKind.String, Type = types.String, S = text.Substring(start, stop - start) });
        start = next;
    }
    return ConstVal { Kind = ConstKind.Slice, Type = sliceType, Items = lines.ToArray() };
}

// The value of a top-level constant (evaluated once; a constant that needs itself is an error).
ConstVal ConstEvalDecl(const ref Compiler cg, int index)
{
    var entry = cg.Consts.Get(index);
    var c = entry.Decl;
    if (entry.State == 2)
        return entry.Value;
    if (entry.State == 1)
        return ConstError(cg, c.Loc, "constant '" + c.Name + "' depends on itself");
    entry.State = 1;
    cg.Consts.Set(index, entry);
    int t = ResolveValueType(cg, c.Type.Id, entry.File, NoEnv());
    if (!IsConstantType(cg, t))
        t = RecoverConstantType(cg, c.Loc, t);
    var sc = ConstScope { File = entry.File, What = "constant '" + c.Name + "'", DeclLoc = c.Loc, Env = NoEnv() };
    // with an unknown type the initializer is still checked; the value is unknown (ConstConvert)
    ConstVal v = IsEmbedExpr(c.Init) && !cg.Types.IsUnknown(t) ? ConstEmbed(cg, c.Init, t) : ConstEvalAs(cg, c.Init, sc, t);
    // enumerators of imported C enums are written as integers
    v = ConstConvert(cg, v, t, c.Init.Loc, cg.Files.Get(entry.File).IsPrelude);
    entry.State = 2;
    entry.Value = v;
    cg.Consts.Set(index, entry);
    return v;
}

// A constant expression whose value becomes a constant of type 'target': integer arithmetic is computed in the target
// type where its operands allow, like at run time (see ArithmeticFrame and EmitExprAs).
ConstVal ConstEvalAs(const ref Compiler cg, Expr e, ConstScope sc, int target)
{
    int frame = ArithmeticFrame(cg, target);
    if (frame == 0 || !IsFramable(cg, e))
        return ConstEval(cg, e, sc);
    return ConstFramed(cg, e, sc, frame);
}

ConstVal ConstFramed(const ref Compiler cg, Expr e, ConstScope sc, int frame)
{
    if (!IsFramable(cg, e) || e.Kind == ExprKind.Unchecked)
        return ConstEval(cg, e, sc);
    if (e.Kind == ExprKind.Unary)
    {
        var u = cg.Tree.GetUnary(e);
        ConstVal v = ConstFramed(cg, u.Operand, sc, frame);
        if (v.Kind == ConstKind.Unknown || v.HasLit || FramedUnaryType(cg, u.Op, ConstProbe(v), frame) != frame)
            return ConstEval(cg, e, sc);
        ConstVal c = ConstConvert(cg, v, frame, e.Loc, false);
        if (u.Op == UnOp.Neg)
            return ConstIntOp(cg, BinOp.Sub, ConstFromPattern(cg, frame, 0ul), c, frame, e.Loc);
        return ConstIntOp(cg, BinOp.BitXor, c, ConstFromPattern(cg, frame, 18446744073709551615ul), frame, e.Loc);
    }
    var b = cg.Tree.GetBinary(e);
    ConstVal l = ConstFramed(cg, b.Lhs, sc, frame);
    ConstVal r = b.Op == BinOp.Shl || b.Op == BinOp.Shr ? ConstEval(cg, b.Rhs, sc) : ConstFramed(cg, b.Rhs, sc, frame);
    if (l.Kind == ConstKind.Unknown || r.Kind == ConstKind.Unknown)
        return l.Kind == ConstKind.Unknown ? l : r;
    if (l.HasLit && r.HasLit && l.Kind == ConstKind.Int && r.Kind == ConstKind.Int)
    {
        // two literals (see FoldLiterals): the result is a value of the frame if it fits (1 + 2 as uint8), otherwise it
        // stays as it is (200 + 100: an int32 that does not convert to uint8)
        ConstVal res = ConstArith(cg, b.Op, l, r, e.Loc);
        if (res.Kind != ConstKind.Int)
            return res;
        ConstVal asLit = res;
        asLit.HasLit = true;
        ConstVal adapted = ConstAdaptLiteral(cg, asLit, frame);
        return adapted.HasLit ? res : adapted;
    }
    if (FramedArithmeticType(cg, b.Op, ConstProbe(l), ConstProbe(r), frame) != frame)
        return ConstArith(cg, b.Op, l, r, e.Loc);
    ConstVal lc = ConstConvert(cg, l.HasLit ? ConstAdaptLiteral(cg, l, frame) : l, frame, e.Loc, false);
    if (b.Op == BinOp.Shl || b.Op == BinOp.Shr)
        return ConstIntOp(cg, b.Op, lc, r, frame, e.Loc);
    ConstVal rc = ConstConvert(cg, r.HasLit ? ConstAdaptLiteral(cg, r, frame) : r, frame, e.Loc, false);
    return ConstIntOp(cg, b.Op, lc, rc, frame, e.Loc);
}

// The value of a member of the enum that is being declared: an integer constant that fits into the base type.
// 'known' holds the members declared so far.
int64 ConstEvalEnumMember(const ref Compiler cg, Expr init, EnumInfo known, int file, string memberName, SourceLoc loc)
{
    var sc = ConstScope { File = file, HasEnum = true, Enum = known, What = "enum member '" + memberName + "'", DeclLoc = loc, Env = NoEnv() };
    ConstVal v = ConstEval(cg, init, sc);
    if (v.Kind == ConstKind.Unknown)
        return 0;
    if (v.Kind != ConstKind.Int)
    {
        Recover(cg, loc, "the value of enum member '" + memberName + "' must be an integer constant");
        return 0;
    }
    if (!ConstFits(cg, v, known.Base))
    {
        Recover(cg, loc, "enum value " + ConstDecimal(v) + " does not fit into " + cg.Types.Name(known.Base));
        return 0;
    }
    return (int64)ConstPattern(v, 64);
}
