// Values and ownership, and conversions between types (port of the first half of CodeGenExpr.cpp).
//
// ARC rules used throughout the code generator:
//  * A variable, field or array slot of an ARC type owns one reference.
//  * An rvalue is either "owned" (it carries a +1 that must be consumed or released) or borrowed.
//  * Consume() turns any value into a +1 value (retaining borrowed ones); it is used when a value is stored,
//    returned or embedded into an aggregate.
//  * HoldTemp() schedules the release of an owned temporary at the end of the current full expression/statement.
//  * Function arguments are passed borrowed; the callee retains parameters it keeps.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// An integer constant of the given (integer, char or enum) type.
Value ConstInt(Compiler cg, int type, int64 value)
{
    return Rvalue(type, value.ToString(), false);
}


Value MakeBool(Compiler cg, string v)
{
    return Rvalue(cg.Types.Bool, v, false);
}

string FloatConstant(Compiler cg, int type, double value)
{
    if (cg.Types.Bits(type) == 32)
        return IrWriter.FloatConst(value);
    return IrWriter.DoubleConst(value);
}

// ---------------------------------------------------------------------------
// Ownership
// ---------------------------------------------------------------------------

Value ToRValue(Compiler cg, Value v)
{
    if (!v.IsLValue)
        return v;
    string loaded = cg.Ir.Load(LlvmType(cg, v.Type), v.V);
    return Rvalue(v.Type, loaded, false);
}

void EmitRetain(Compiler cg, int type, string v)
{
    if (!NeedsArc(cg, type))
        return;
    cg.Ir.Call("void", RetainFunction(cg, type), LlvmType(cg, type) + " " + v);
}

void EmitRelease(Compiler cg, int type, string v)
{
    if (!NeedsArc(cg, type))
        return;
    cg.Ir.Call("void", ReleaseFunction(cg, type), LlvmType(cg, type) + " " + v);
}

// The operand of the value with a +1 reference count.
string Consume(Compiler cg, Value v)
{
    Value r = ToRValue(cg, v);
    if (!r.Owned && NeedsArc(cg, r.Type))
        EmitRetain(cg, r.Type, r.V);
    return r.V;
}

// An owned temporary is released at the end of the statement.
void HoldTemp(Compiler cg, Value v)
{
    if (v.Owned && !v.IsLValue && NeedsArc(cg, v.Type))
        cg.Fn[0].Temps.Add(TempRelease { Type = v.Type, Value = v.V });
}

// Releases the temporaries above 'mark'; with 'pop' they are also forgotten.
void FlushTemps(Compiler cg, int mark, bool pop)
{
    var temps = cg.Fn[0].Temps;
    if (cg.Ir.BlockOpen())
    {
        for (var i = temps.Count(); i > mark; i -= 1)
        {
            var t = temps.Get(i - 1);
            EmitRelease(cg, t.Type, t.Value);
        }
    }
    if (pop)
    {
        while (temps.Count() > mark)
            temps.RemoveAt(temps.Count() - 1);
    }
}

// Stores a +1 value into a slot and releases what the slot held before.
void StoreSlot(Compiler cg, int type, string addr, string newOwned, bool releaseOld)
{
    string llvm = LlvmType(cg, type);
    if (releaseOld && NeedsArc(cg, type))
    {
        string old = cg.Ir.Load(llvm, addr);
        cg.Ir.Store(llvm, newOwned, addr);
        EmitRelease(cg, type, old);
    }
    else
    {
        cg.Ir.Store(llvm, newOwned, addr);
    }
}

void RequireUnsafe(Compiler cg, SourceLoc loc, string what)
{
    if (cg.Fn[0].UnsafeDepth == 0)
        Fail(cg, loc, what + " is only allowed in an 'unsafe' context");
}

// The type of a declaration in the current function ('var' is not handled here).
int DeclTypeOf(Compiler cg, TypeRef t)
{
    var f = cg.Fn[0];
    return ResolveValueType(cg, t.Id, f.File, f.Env);
}

// ---------------------------------------------------------------------------
// Numeric conversions
// ---------------------------------------------------------------------------

bool LiteralFits(Compiler cg, Value v, int to)
{
    var types = cg.Types;
    if (v.LitIsFloat)
        return false;
    if (types.IsChar(to))
        return v.LitInt >= 0 && v.LitInt <= 255;
    if (!types.IsInt(to))
        return false;
    int bits = types.Bits(to);
    if (bits >= 64)
        return types.IsSigned(to) || v.LitInt >= 0;
    int64 one = 1;
    if (types.IsSigned(to))
        return v.LitInt >= -(one << (bits - 1)) && v.LitInt < (one << (bits - 1));
    return v.LitInt >= 0 && v.LitInt < (one << bits);
}

bool IsIntLike(Compiler cg, int t)
{
    var k = cg.Types.Kind(t);
    return k == TypeKind.Int || k == TypeKind.Char || k == TypeKind.Enum;
}

bool SignedOf(Compiler cg, int t)
{
    var k = cg.Types.Kind(t);
    return (k == TypeKind.Int || k == TypeKind.Enum) && cg.Types.IsSigned(t);
}

// Converts a number (integer, char, enum, float) to another numeric type; no checks, floats saturate.
string NumericConvert(Compiler cg, string v, int from, int to)
{
    var types = cg.Types;
    string src = LlvmType(cg, from);
    string dst = LlvmType(cg, to);
    if (IsIntLike(cg, from) && IsIntLike(cg, to))
    {
        int fb = types.Bits(from);
        int tb = types.Bits(to);
        if (fb == tb)
            return v;
        if (fb > tb)
            return cg.Ir.Cast("trunc", src, v, dst);
        return cg.Ir.Cast(SignedOf(cg, from) ? "sext" : "zext", src, v, dst);
    }
    if (IsIntLike(cg, from) && types.IsFloat(to))
        return cg.Ir.Cast(SignedOf(cg, from) ? "sitofp" : "uitofp", src, v, dst);
    if (types.IsFloat(from) && IsIntLike(cg, to))
    {
        string kind = SignedOf(cg, to) ? "fptosi" : "fptoui";
        string intrinsic = "llvm." + kind + ".sat." + dst + "." + src;
        cg.Ir.Declare(intrinsic, "declare " + dst + " @" + intrinsic + "(" + src + ")");
        return cg.Ir.Call(dst, "@" + intrinsic, src + " " + v);
    }
    if (types.IsFloat(from) && types.IsFloat(to))
    {
        if (types.Bits(from) == types.Bits(to))
            return v;
        return cg.Ir.Cast(types.Bits(from) > types.Bits(to) ? "fptrunc" : "fpext", src, v, dst);
    }
    Fail(cg, SourceLoc { }, "internal error: invalid numeric conversion");
    return v;
}

// ---------------------------------------------------------------------------
// Implicit conversions: cost (for overload resolution) and emission
// ---------------------------------------------------------------------------

// Cost of an implicit conversion between integer types, or -1.
int ImplicitIntCost(Compiler cg, int from, int to)
{
    var types = cg.Types;
    if (!(types.IsIntegral(from) && types.IsIntegral(to)))
        return -1;
    int fb = types.Bits(from);
    int tb = types.Bits(to);
    if (types.IsChar(from) != types.IsChar(to) && fb == 8 && tb == 8)
    {
        // char <-> uint8
        int other = types.IsChar(from) ? to : from;
        return types.IsInt(other) && !types.IsSigned(other) ? 1 : -1;
    }
    bool fromSigned = types.IsInt(from) && types.IsSigned(from);
    bool toSigned = types.IsInt(to) && types.IsSigned(to);
    // Pointer-sized integers (like C#): int32 and smaller convert to nint/nuint, nint/nuint to the 64-bit types.
    if (types.IsNative(to) && !types.IsNative(from) && fb <= 32)
        return (toSigned ? (fromSigned || fb < 32) : !fromSigned) ? 2 : -1;
    if (types.IsNative(from) && !types.IsNative(to) && tb >= 64 && fromSigned == toSigned)
        return 2;
    if (tb > fb && (!fromSigned || toSigned))
        return 2 + (tb - fb) / 16;
    return -1;
}

// The cost of converting the value to 'to' (0 = same type, -1 = not possible).
int ConversionCost(Compiler cg, Value v, int to)
{
    var types = cg.Types;
    int from = v.Type;
    if (from == to)
        return 0;

    if (v.HasLit)
    {
        if (!v.LitIsFloat && LiteralFits(cg, v, to))
            return 1;
        // Integer literals prefer double (exact), float literals prefer float.
        if (types.IsFloat(to))
            return (v.LitIsFloat || types.Bits(to) == 64) ? 1 : 2;
    }
    var fromKind = types.Kind(from);
    if (fromKind == TypeKind.Null)
    {
        var toKind = types.Kind(to);
        return (toKind == TypeKind.Pointer || toKind == TypeKind.String || toKind == TypeKind.Array ||
                toKind == TypeKind.Optional || toKind == TypeKind.Function || toKind == TypeKind.SharedPtr) ? 1 : -1;
    }
    if (fromKind == TypeKind.MethodGroup)
    {
        string unused = "";
        return types.IsFunction(to) && ResolveGroup(cg, v, to, ref unused) >= 0 ? 1 : -1;
    }
    if (fromKind == TypeKind.ErrorLit)
        return types.IsError(to) ? 1 : -1;

    int c = ImplicitIntCost(cg, from, to);
    if (c >= 0)
        return c;
    if (types.IsIntegral(from) && types.IsFloat(to))
        return types.Bits(to) == 64 ? 6 : 7; // worse than any integer widening; double is preferred (exact for int32)
    if (types.IsFloat(from) && types.IsFloat(to) && types.Bits(from) < types.Bits(to))
        return 2;
    if (types.IsPointer(from) && types.IsPointer(to) && types.IsVoid(types.Elem(to)))
        return 2;
    if (types.IsStruct(from) && types.IsStruct(to))
    {
        var path = new int[0];
        if (StructIsAncestor(cg, to, from, ref path))
            return 2;
    }
    if (types.IsResultLike(to) && !types.IsResultLike(from))
    {
        int inner = ConversionCost(cg, v, types.Elem(to));
        if (inner >= 0)
            return inner + 3;
    }
    return -1;
}

// A literal that takes the type of the operand it is combined with.
Value AdaptLiteral(Compiler cg, Value v, int to)
{
    if (!v.HasLit)
        return v;
    if (!v.LitIsFloat && LiteralFits(cg, v, to))
        return ConstInt(cg, to, v.LitInt);
    if (cg.Types.IsFloat(to))
        return Rvalue(to, FloatConstant(cg, to, v.LitIsFloat ? v.LitFloat : (double)v.LitInt), false);
    return v;
}

Value ConvertValue(Compiler cg, Value v, int to, SourceLoc loc)
{
    var types = cg.Types;
    int from = v.Type;
    if (from == to)
        return ToRValue(cg, v);
    if (types.Kind(from) == TypeKind.MethodGroup)
        return ConvertGroup(cg, v, to, loc);

    if (ConversionCost(cg, v, to) < 0)
    {
        string hint = "";
        if (types.IsNumeric(from) && types.IsNumeric(to))
            hint = " (an explicit cast is required)";
        Fail(cg, loc, "cannot implicitly convert '" + types.Name(from) + "' to '" + types.Name(to) + "'" + hint);
    }

    if (v.HasLit)
    {
        Value a = AdaptLiteral(cg, v, to);
        if (a.Type == to)
            return a;
    }

    var fromKind = types.Kind(from);
    if (fromKind == TypeKind.Null)
    {
        if (types.IsOptional(to))
            return Rvalue(to, "zeroinitializer", false);
        return Rvalue(to, "null", false);
    }
    if (fromKind == TypeKind.ErrorLit)
    {
        Value r = ToRValue(cg, v);
        string litIr = LlvmType(cg, from);
        string msg = cg.Ir.ExtractValue(litIr, r.V, "0");
        string code = cg.Ir.ExtractValue(litIr, r.V, "1");
        return Rvalue(to, MakeErr(cg, to, msg, code), true);
    }
    if (types.IsNumeric(from) && types.IsNumeric(to))
    {
        Value r = ToRValue(cg, v);
        return Rvalue(to, NumericConvert(cg, r.V, from, to), false);
    }
    if (types.IsPointer(from) && types.IsPointer(to))
        return Rvalue(to, ToRValue(cg, v).V, false);
    if (types.IsStruct(from) && types.IsStruct(to))
    {
        // upcast: the base struct is the first member of the derived one
        var path = new int[0];
        StructIsAncestor(cg, to, from, ref path);
        Value r = ToRValue(cg, v);
        HoldTemp(cg, r);
        return Rvalue(to, cg.Ir.ExtractValue(LlvmType(cg, from), r.V, IndexList(path)), false);
    }
    if (types.IsResultLike(to))
    {
        Value inner = ConvertValue(cg, v, types.Elem(to), loc);
        string payload = Consume(cg, inner);
        return Rvalue(to, MakeSome(cg, to, payload), NeedsArc(cg, to));
    }
    Fail(cg, loc, "cannot implicitly convert '" + types.Name(from) + "' to '" + types.Name(to) + "'");
    return v;
}

// The type of an arithmetic result when two numeric types meet (C# rules).
int PromoteTypes(Compiler cg, int a, int b, SourceLoc loc)
{
    var types = cg.Types;
    if (types.IsFloat(a) || types.IsFloat(b))
    {
        if ((types.IsFloat(a) && types.Bits(a) == 64) || (types.IsFloat(b) && types.Bits(b) == 64))
            return types.F64;
        return types.F32;
    }

    // nint/nuint promote like the fixed-size integer of the same width; the result stays native when the other
    // operand is native as well or smaller than a pointer.
    if (types.IsNative(a) || types.IsNative(b))
    {
        int pa = types.IsNative(a) ? types.IntType(types.Bits(a), types.IsSigned(a)) : a;
        int pb = types.IsNative(b) ? types.IntType(types.Bits(b), types.IsSigned(b)) : b;
        int r = PromoteTypes(cg, pa, pb, loc);
        int native = types.IsNative(a) ? a : b;
        int other = native == a ? b : a;
        int plainNative = types.IsNative(native) ? types.IntType(types.Bits(native), types.IsSigned(native)) : native;
        if (r == plainNative && (types.IsNative(other) || types.IsChar(other) || types.Bits(other) < types.Bits(native)))
            return native;
        return r;
    }
    int x = (types.IsChar(a) || types.Bits(a) < 32) ? types.I32 : a;
    int y = (types.IsChar(b) || types.Bits(b) < 32) ? types.I32 : b;
    if (x == y)
        return x;
    if (x == types.U64 || y == types.U64)
    {
        int other = x == types.U64 ? y : x;
        if (types.IsSigned(other))
            Fail(cg, loc, "operator cannot mix 'uint64' and signed types, use an explicit cast");
        return types.U64;
    }
    return types.I64; // int64, or int32 mixed with uint32
}
