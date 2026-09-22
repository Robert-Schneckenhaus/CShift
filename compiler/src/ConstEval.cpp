// The compile-time evaluator: the value of a constant expression is computed by the compiler, not by generated code.
//
// It follows the rules of the code that is generated for the same expression at run time (the type of literals, the
// promotion of small integers, checked arithmetic, shifts, comparisons, conversions, string concatenation), but an
// overflow or a division by zero is an error of the compilation. Constants (top level and local), the values of enum
// members and sizeof(T) are evaluated with it. The same code exists in CShift for cshc (selfhost/src/CodeGen/ConstEval.csh).
//
// Integers are kept as sign and magnitude (the value of every integer type fits into a 64 bit magnitude), so no wider
// integer type is needed.

#include "CodeGen.h"

#include <cmath>
#include <cstdio>

namespace
{
uint64_t maskOf(int bits)
{
    return bits >= 64 ? ~0ull : ((1ull << bits) - 1);
}

bool signedType(const Type* t)
{
    return (t->isInt() || t->isEnum()) && t->isSigned;
}

bool intLike(const Type* t)
{
    return t->isInt() || t->isChar() || t->isEnum();
}

// The two's complement bits of an integer value, in 'bits' bits.
uint64_t patternOf(const ConstVal& v, int bits)
{
    uint64_t p = (v.neg && v.mag) ? (~v.mag + 1) : v.mag;
    return p & maskOf(bits);
}

// Sets the value of 'v' (its type is set) from two's complement bits.
void fromPattern(ConstVal& v, uint64_t p)
{
    int bits = v.type->bits;
    p &= maskOf(bits);
    if (signedType(v.type) && bits > 0 && ((p >> (bits - 1)) & 1))
    {
        v.neg = true;
        v.mag = (~p + 1) & maskOf(bits);
    }
    else
    {
        v.neg = false;
        v.mag = p;
    }
}

bool fitsType(const ConstVal& v, const Type* t)
{
    int bits = t->bits;
    if (signedType(t))
    {
        uint64_t limit = 1ull << (bits - 1);
        return v.neg ? v.mag <= limit : v.mag < limit;
    }
    return (!v.neg || v.mag == 0) && v.mag <= maskOf(bits);
}

std::string decimalOf(const ConstVal& v)
{
    return std::string(v.neg && v.mag ? "-" : "") + std::to_string(v.mag);
}

ConstVal makeInt(Type* t, bool neg, uint64_t mag, bool lit = false)
{
    ConstVal v;
    v.kind = ConstVal::Int;
    v.type = t;
    v.neg = neg && mag != 0;
    v.mag = mag;
    v.hasLit = lit;
    return v;
}

ConstVal makeFloat(Type* t, double f, bool lit = false)
{
    ConstVal v;
    v.kind = ConstVal::Float;
    v.type = t;
    v.f = t->bits == 32 ? (double)(float)f : f;
    v.hasLit = lit;
    return v;
}

// The value of an integer as a floating point number (a float32 is rounded once, directly from the integer).
double toFloat(const ConstVal& v, const Type* to)
{
    double m = to->bits == 32 ? (double)(float)v.mag : (double)v.mag;
    return v.neg ? -m : m;
}

// A + B, A - B, A * B of sign/magnitude numbers; false if the magnitude does not fit into 64 bits.
bool addSigned(bool an, uint64_t am, bool bn, uint64_t bm, bool& rn, uint64_t& rm)
{
    if (an == bn)
    {
        rn = an;
        rm = am + bm;
        return rm >= am;
    }
    if (am >= bm)
    {
        rn = an;
        rm = am - bm;
    }
    else
    {
        rn = bn;
        rm = bm - am;
    }
    if (rm == 0)
        rn = false;
    return true;
}

// A floating point number converted to an integer type: truncated and clamped to the range (NaN gives 0), like the
// llvm.fptosi.sat / fptoui.sat intrinsics that the generated code uses.
ConstVal saturate(double d, Type* to)
{
    ConstVal r;
    r.kind = ConstVal::Int;
    r.type = to;
    int bits = to->bits;
    if (std::isnan(d))
        return r;
    if (signedType(to))
    {
        uint64_t limit = 1ull << (bits - 1); // the magnitude of the minimum
        double top = std::ldexp(1.0, bits - 1);
        if (d >= top)
        {
            r.mag = limit - 1;
            return r;
        }
        if (d <= -top)
        {
            r.neg = true;
            r.mag = limit;
            return r;
        }
        double t = std::trunc(d);
        r.neg = t < 0;
        r.mag = (uint64_t)std::fabs(t);
        return r;
    }
    double top = std::ldexp(1.0, bits);
    if (d >= top)
    {
        r.mag = maskOf(bits);
        return r;
    }
    if (d <= 0)
        return r;
    r.mag = (uint64_t)std::trunc(d);
    return r;
}

// The order of two integer values: -1, 0 or 1.
int orderOf(const ConstVal& a, const ConstVal& b)
{
    bool an = a.neg && a.mag != 0, bn = b.neg && b.mag != 0;
    if (an != bn)
        return an ? -1 : 1;
    if (a.mag == b.mag)
        return 0;
    return ((a.mag < b.mag) != an) ? -1 : 1;
}
} // namespace

// ---------------------------------------------------------------------------
// Conversions
// ---------------------------------------------------------------------------

// A probe for conversionCost: the type and the literal information of a constant.
static Value probeOf(const ConstVal& v)
{
    Value p;
    p.type = v.type;
    p.hasLit = v.hasLit;
    p.litIsFloat = v.kind == ConstVal::Float;
    p.litFloat = v.f;
    p.litInt = v.neg ? -(int64_t)v.mag : (int64_t)v.mag;
    return p;
}

ConstVal CodeGen::constNumericConvert(const ConstVal& v, Type* to)
{
    Type* from = v.type;
    if (intLike(from) && intLike(to))
    {
        ConstVal r;
        r.kind = ConstVal::Int;
        r.type = to;
        fromPattern(r, patternOf(v, 64));
        return r;
    }
    if (intLike(from) && to->isFloat())
        return makeFloat(to, toFloat(v, to));
    if (from->isFloat() && intLike(to))
        return saturate(v.f, to);
    if (from->isFloat() && to->isFloat())
        return makeFloat(to, v.f);
    err(SourceLoc{}, "internal error: invalid numeric conversion");
}

// An unsuffixed literal takes the type of the value it is combined with, if it fits.
ConstVal CodeGen::constAdaptLiteral(const ConstVal& v, Type* to)
{
    if (!v.hasLit)
        return v;
    if (v.kind == ConstVal::Int)
    {
        bool fits = to->isChar() ? ((!v.neg || v.mag == 0) && v.mag <= 255) : (to->isInt() && fitsType(v, to));
        if (fits)
            return makeInt(to, v.neg, v.mag);
    }
    if (to->isFloat())
        return makeFloat(to, v.kind == ConstVal::Float ? v.f : toFloat(v, to));
    return v;
}

// The implicit conversion of a value to a type (the counterpart of convertValue).
ConstVal CodeGen::constConvert(const ConstVal& v, Type* to, SourceLoc loc, bool allowEnumInt)
{
    Type* from = v.type;
    if (from == to)
        return v;
    // enumerators of imported C enums are written as integers
    if (allowEnumInt && to->isEnum() && v.kind == ConstVal::Int && !from->isEnum())
    {
        if (!fitsType(v, to->elem))
            err(loc, "enum value " + decimalOf(v) + " does not fit into " + to->elem->name);
        ConstVal r;
        r.kind = ConstVal::Int;
        r.type = to;
        fromPattern(r, patternOf(v, 64));
        return r;
    }
    Value probe = probeOf(v);
    if (conversionCost(probe, to) < 0)
    {
        std::string hint;
        if (from->isNumeric() && to->isNumeric())
            hint = " (an explicit cast is required)";
        err(loc, "cannot implicitly convert '" + from->name + "' to '" + to->name + "'" + hint);
    }
    if (v.hasLit)
    {
        ConstVal a = constAdaptLiteral(v, to);
        if (a.type == to)
            return a;
    }
    if (from->isNumeric() && to->isNumeric())
        return constNumericConvert(v, to);
    err(loc, "cannot implicitly convert '" + from->name + "' to '" + to->name + "'");
}

// The text of a value in a string concatenation.
std::string CodeGen::constToText(const ConstVal& v)
{
    switch (v.kind)
    {
    case ConstVal::String: return v.s;
    case ConstVal::Bool: return v.b ? "true" : "false";
    case ConstVal::Float:
    {
        char buffer[64];
        std::snprintf(buffer, sizeof(buffer), v.type->bits == 32 ? "%.7g" : "%.15g", v.f);
        return buffer;
    }
    case ConstVal::Int:
        if (v.type->isChar())
            return std::string(1, (char)v.mag);
        return decimalOf(v);
    }
    return "";
}

// The value as an LLVM constant.
Value CodeGen::constToValue(const ConstVal& v)
{
    Value r;
    switch (v.kind)
    {
    case ConstVal::Int:
        r = constInt(v.type, (int64_t)patternOf(v, 64));
        break;
    case ConstVal::Float:
        r = Value::rvalue(v.type, llvm::ConstantFP::get(llvmTypeOf(v.type), v.f));
        break;
    case ConstVal::Bool:
        r = boolValue(builder.getInt1(v.b));
        break;
    case ConstVal::String:
        r = Value::rvalue(types.stringTy, stringLiteral(v.s));
        break;
    }
    if (v.hasLit)
    {
        r.hasLit = true;
        r.litIsFloat = v.kind == ConstVal::Float;
        r.litFloat = v.f;
        r.litInt = v.neg ? -(int64_t)v.mag : (int64_t)v.mag;
    }
    return r;
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

ConstVal CodeGen::constIntOp(BinOp op, const ConstVal& l, const ConstVal& r, Type* t, SourceLoc loc)
{
    ConstVal out;
    out.kind = ConstVal::Int;
    out.type = t;
    int bits = t->bits;
    bool sgn = signedType(t);
    auto overflow = [&]() { err(loc, "integer overflow in a constant expression (the value does not fit into " + t->name + ")"); };
    switch (op)
    {
    case BinOp::Add:
    case BinOp::Sub:
    case BinOp::Mul:
    {
        bool rn = false;
        uint64_t rm = 0;
        bool ok;
        if (op == BinOp::Mul)
        {
            ok = l.mag == 0 || r.mag <= ~0ull / l.mag;
            rm = l.mag * r.mag;
            rn = (l.neg != r.neg) && rm != 0;
        }
        else
        {
            ok = addSigned(l.neg, l.mag, op == BinOp::Add ? r.neg : !r.neg, r.mag, rn, rm);
        }
        out.neg = rn;
        out.mag = rm;
        if (!ok || !fitsType(out, t))
            overflow();
        return out;
    }
    case BinOp::Div:
    case BinOp::Rem:
    {
        if (r.mag == 0)
            err(loc, "division by zero in constant expression");
        if (sgn && l.neg && l.mag == (1ull << (bits - 1)) && r.neg && r.mag == 1)
            overflow(); // the smallest value divided by -1
        uint64_t q = l.mag / r.mag;
        uint64_t rem = l.mag % r.mag;
        if (op == BinOp::Div)
        {
            out.neg = (l.neg != r.neg) && q != 0;
            out.mag = q;
        }
        else
        {
            out.neg = l.neg && rem != 0;
            out.mag = rem;
        }
        return out;
    }
    case BinOp::BitAnd:
    case BinOp::BitOr:
    case BinOp::BitXor:
    {
        uint64_t a = patternOf(l, bits), b = patternOf(r, bits);
        fromPattern(out, op == BinOp::BitAnd ? (a & b) : op == BinOp::BitOr ? (a | b) : (a ^ b));
        return out;
    }
    case BinOp::Shl:
    case BinOp::Shr:
    {
        uint64_t a = patternOf(l, bits);
        unsigned count = (unsigned)(patternOf(r, 64) & (uint64_t)(bits - 1));
        uint64_t res;
        if (op == BinOp::Shl)
            res = a << count;
        else if (sgn && ((a >> (bits - 1)) & 1))
            res = ~((~a & maskOf(bits)) >> count); // arithmetic shift of a negative value
        else
            res = a >> count;
        fromPattern(out, res);
        return out;
    }
    default: break;
    }
    err(SourceLoc{}, "internal error: invalid integer operation");
}

ConstVal CodeGen::constArith(BinOp op, ConstVal l, ConstVal r, SourceLoc loc)
{
    // String concatenation (the other operand may be any primitive).
    if (op == BinOp::Add && (l.type->isString() || r.type->isString()))
    {
        ConstVal out;
        out.kind = ConstVal::String;
        out.type = types.stringTy;
        out.s = constToText(l) + constToText(r);
        return out;
    }

    // Bit operations on enums and bools.
    if (l.type == r.type && (op == BinOp::BitAnd || op == BinOp::BitOr || op == BinOp::BitXor))
    {
        if (l.type->isBool())
        {
            ConstVal out = l;
            out.b = op == BinOp::BitAnd ? (l.b && r.b) : op == BinOp::BitOr ? (l.b || r.b) : (l.b != r.b);
            out.hasLit = false;
            return out;
        }
        if (l.type->isEnum())
            return constIntOp(op, l, r, l.type, loc);
    }

    if (!l.type->isNumeric() || !r.type->isNumeric())
    {
        static const char* names[] = {"+", "-", "*", "/", "%", "&", "|", "^", "<<", ">>"};
        err(loc, std::string("operator '") + names[(int)op] + "' cannot be applied to '" + l.type->name + "' and '" + r.type->name + "'");
    }

    // Shifts: the result has the (promoted) type of the left operand.
    if (op == BinOp::Shl || op == BinOp::Shr)
    {
        if (!l.type->isIntegral() || !r.type->isIntegral())
            err(loc, "shift operators require integer operands");
        Type* t = promoteTypes(l.type, l.type, loc);
        ConstVal lv = constConvert(l.hasLit ? constAdaptLiteral(l, t) : l, t, loc);
        return constIntOp(op, lv, r, t, loc);
    }

    // Adapt literals to the other operand's type.
    if (l.hasLit && !r.hasLit)
        l = constAdaptLiteral(l, r.type);
    else if (r.hasLit && !l.hasLit)
        r = constAdaptLiteral(r, l.type);

    Type* t = promoteTypes(l.type, r.type, loc);
    ConstVal lv = constConvert(l, t, loc);
    ConstVal rv = constConvert(r, t, loc);

    if (t->isFloat())
    {
        double res;
        switch (op)
        {
        case BinOp::Add: res = lv.f + rv.f; break;
        case BinOp::Sub: res = lv.f - rv.f; break;
        case BinOp::Mul: res = lv.f * rv.f; break;
        case BinOp::Div: res = lv.f / rv.f; break;
        case BinOp::Rem: res = std::fmod(lv.f, rv.f); break;
        default: err(loc, "bit operations are not defined for floating point values");
        }
        return makeFloat(t, res);
    }
    return constIntOp(op, lv, rv, t, loc);
}

ConstVal CodeGen::constCompare(BinOp op, ConstVal l, ConstVal r, SourceLoc loc)
{
    bool isEq = op == BinOp::Eq || op == BinOp::Ne;
    auto boolResult = [&](bool value) {
        ConstVal out;
        out.kind = ConstVal::Bool;
        out.type = types.boolTy;
        out.b = value;
        return out;
    };
    // the order of two values: -1, 0, 1 (2 = unordered)
    auto decide = [&](int order) {
        switch (op)
        {
        case BinOp::Eq: return boolResult(order == 0);
        case BinOp::Ne: return boolResult(order != 0);
        case BinOp::Lt: return boolResult(order == -1);
        case BinOp::Gt: return boolResult(order == 1);
        case BinOp::Le: return boolResult(order == -1 || order == 0);
        default: return boolResult(order == 1 || order == 0);
        }
    };

    if (l.type->isString() && r.type->isString())
    {
        if (!isEq)
            err(loc, "strings can only be compared with '==' and '!='");
        return boolResult((l.s == r.s) == (op == BinOp::Eq));
    }

    if (l.hasLit && !r.hasLit)
        l = constAdaptLiteral(l, r.type);
    else if (r.hasLit && !l.hasLit)
        r = constAdaptLiteral(r, l.type);

    // Bool and enum.
    if (l.type == r.type && (l.type->isBool() || l.type->isEnum()))
    {
        if (l.type->isBool())
        {
            if (!isEq)
                err(loc, "bool values can only be compared with '==' and '!='");
            return boolResult((l.b == r.b) == (op == BinOp::Eq));
        }
        return decide(orderOf(l, r));
    }

    if (!l.type->isNumeric() || !r.type->isNumeric())
        err(loc, "cannot compare '" + l.type->name + "' with '" + r.type->name + "'");

    Type* t = promoteTypes(l.type, r.type, loc);
    ConstVal lv = constConvert(l, t, loc);
    ConstVal rv = constConvert(r, t, loc);
    if (t->isFloat())
    {
        if (std::isnan(lv.f) || std::isnan(rv.f))
            return boolResult(op == BinOp::Ne); // only != is true for unordered values
        return decide(lv.f < rv.f ? -1 : lv.f > rv.f ? 1 : 0);
    }
    return decide(orderOf(lv, rv));
}

// ---------------------------------------------------------------------------
// The evaluator
// ---------------------------------------------------------------------------

static bool dottedNameOf(Expr* e, std::string& out)
{
    if (e->kind == ExprKind::Name)
    {
        out = static_cast<NameExpr*>(e)->name;
        return true;
    }
    if (e->kind == ExprKind::Member && !static_cast<MemberExpr*>(e)->viaArrow)
    {
        std::string left;
        if (!dottedNameOf(static_cast<MemberExpr*>(e)->object.get(), left))
            return false;
        out = left + "." + static_cast<MemberExpr*>(e)->name;
        return true;
    }
    return false;
}

bool CodeGen::isConstantType(Type* t) const
{
    return t->isNumeric() || t->isBool() || t->isString() || t->isEnum();
}

ConstVal CodeGen::constEval(Expr* e, const ConstScope& sc)
{
    auto notConstant = [&]() -> ConstVal {
        err(sc.declLoc, "the initializer of " + sc.what + " must be a constant expression (literals, operators, other constants)");
        return ConstVal{};
    };

    switch (e->kind)
    {
    case ExprKind::IntLit:
    {
        auto* l = static_cast<IntLitExpr*>(e);
        if (l->isUnsigned || l->isLong)
        {
            Type* t;
            if (l->isUnsigned && l->isLong)
                t = types.u64;
            else if (l->isUnsigned)
                t = l->value <= UINT32_MAX ? types.u32 : types.u64;
            else
                t = l->value <= (uint64_t)INT64_MAX ? types.i64 : types.u64;
            return makeInt(t, false, l->value);
        }
        if (l->value <= (uint64_t)INT32_MAX)
            return makeInt(types.i32, false, l->value, true);
        if (l->value <= (uint64_t)INT64_MAX)
            return makeInt(types.i64, false, l->value, true);
        return makeInt(types.u64, false, l->value);
    }
    case ExprKind::FloatLit:
    {
        auto* l = static_cast<FloatLitExpr*>(e);
        return l->isFloat32 ? makeFloat(types.f32, l->value) : makeFloat(types.f64, l->value, true);
    }
    case ExprKind::CharLit:
        return makeInt(types.charTy, false, (uint64_t)static_cast<CharLitExpr*>(e)->value);
    case ExprKind::StringLit:
    {
        ConstVal v;
        v.kind = ConstVal::String;
        v.type = types.stringTy;
        v.s = static_cast<StringLitExpr*>(e)->value;
        return v;
    }
    case ExprKind::BoolLit:
    {
        ConstVal v;
        v.kind = ConstVal::Bool;
        v.type = types.boolTy;
        v.b = static_cast<BoolLitExpr*>(e)->value;
        return v;
    }
    case ExprKind::Name:
    {
        const std::string& name = static_cast<NameExpr*>(e)->name;
        if (sc.enumInfo)
        {
            // an earlier member of the enum that is being declared
            for (const auto& m : sc.enumInfo->members)
                if (m.first == name)
                {
                    ConstVal v;
                    v.kind = ConstVal::Int;
                    v.type = sc.enumInfo->base;
                    fromPattern(v, (uint64_t)m.second);
                    return v;
                }
        }
        if (sc.locals)
        {
            if (ScopeVar* local = findLocal(name))
            {
                if (!local->isConstant)
                    return notConstant(); // a local variable hides a constant of the same name
                return local->constValue;
            }
        }
        if (ConstDecl* c = lookupConst(sc.file, name))
            return constEvalDecl(c);
        return notConstant();
    }
    case ExprKind::Member:
    {
        // Ns.Constant or Enum.Member
        auto* m = static_cast<MemberExpr*>(e);
        std::string dotted;
        if (!dottedNameOf(m->object.get(), dotted))
            return notConstant();
        if (sc.locals && findLocal(dotted.substr(0, dotted.find('.'))))
            return notConstant();
        if (ConstDecl* c = lookupConst(sc.file, dotted + "." + m->name))
            return constEvalDecl(c);
        const TypeDeclEntry* entry = lookupTypeDecl(sc.file, dotted);
        if (entry && entry->kind == TypeDeclEntry::Enum)
        {
            Type* et = getEnumType(entry->enumDecl);
            for (const auto& member : et->en->members)
                if (member.first == m->name)
                {
                    ConstVal v;
                    v.kind = ConstVal::Int;
                    v.type = et;
                    fromPattern(v, (uint64_t)member.second);
                    return v;
                }
            err(e->loc, "enum '" + et->name + "' has no member '" + m->name + "'");
        }
        return notConstant();
    }
    case ExprKind::Unary:
    {
        auto* u = static_cast<UnaryExpr*>(e);
        if (u->op == UnOp::Deref || u->op == UnOp::AddrOf)
            return notConstant();
        ConstVal v = constEval(u->operand.get(), sc);
        switch (u->op)
        {
        case UnOp::Neg:
        case UnOp::Plus:
        {
            if (v.hasLit && u->op == UnOp::Neg)
            {
                if (v.kind == ConstVal::Float)
                {
                    v.f = -v.f;
                    return v;
                }
                // -n of an integer literal: int32 if it fits, otherwise int64
                bool neg = !v.neg && v.mag != 0;
                bool fits32 = neg ? v.mag <= (1ull << 31) : v.mag < (1ull << 31);
                return makeInt(fits32 ? types.i32 : types.i64, neg, v.mag, true);
            }
            if (!v.type->isNumeric())
                err(e->loc, "unary '-' cannot be applied to '" + v.type->name + "'");
            Type* t = v.type->isFloat() ? v.type : promoteTypes(v.type, v.type, e->loc);
            ConstVal c = constConvert(v, t, e->loc);
            if (u->op == UnOp::Plus)
                return c;
            if (t->isFloat())
                return makeFloat(t, -c.f);
            if (!t->isSigned)
                err(e->loc, "unary '-' cannot be applied to unsigned type '" + t->name + "'");
            ConstVal zero = makeInt(t, false, 0);
            return constIntOp(BinOp::Sub, zero, c, t, e->loc);
        }
        case UnOp::Not:
        {
            if (v.type->isBool())
            {
                v.b = !v.b;
                v.hasLit = false;
                return v;
            }
            err(e->loc, "operator '!' cannot be applied to '" + v.type->name + "'");
        }
        case UnOp::BitNot:
        {
            if (v.type->isEnum())
            {
                ConstVal r;
                r.kind = ConstVal::Int;
                r.type = v.type;
                fromPattern(r, ~patternOf(v, v.type->bits));
                return r;
            }
            if (!v.type->isIntegral())
                err(e->loc, "operator '~' cannot be applied to '" + v.type->name + "'");
            Type* t = promoteTypes(v.type, v.type, e->loc);
            ConstVal c = constConvert(v, t, e->loc);
            ConstVal r;
            r.kind = ConstVal::Int;
            r.type = t;
            fromPattern(r, ~patternOf(c, t->bits));
            return r;
        }
        default: break;
        }
        return notConstant();
    }
    case ExprKind::Binary:
    {
        auto* b = static_cast<BinaryExpr*>(e);
        if (b->op == BinOp::LogAnd || b->op == BinOp::LogOr)
        {
            // the right side is only evaluated if it can change the result
            ConstVal l = constEval(b->lhs.get(), sc);
            if (!l.type->isBool())
                err(b->lhs->loc, "a condition must be of type 'bool', not '" + l.type->name + "' (there is no implicit conversion to bool)");
            if (b->op == BinOp::LogAnd ? !l.b : l.b)
            {
                l.hasLit = false;
                return l;
            }
            ConstVal r = constEval(b->rhs.get(), sc);
            if (!r.type->isBool())
                err(b->rhs->loc, "a condition must be of type 'bool', not '" + r.type->name + "' (there is no implicit conversion to bool)");
            return r;
        }
        ConstVal l = constEval(b->lhs.get(), sc);
        ConstVal r = constEval(b->rhs.get(), sc);
        switch (b->op)
        {
        case BinOp::Eq: case BinOp::Ne: case BinOp::Lt: case BinOp::Gt: case BinOp::Le: case BinOp::Ge:
            return constCompare(b->op, l, r, e->loc);
        default:
            return constArith(b->op, l, r, e->loc);
        }
    }
    case ExprKind::Cast:
    {
        auto* c = static_cast<CastExpr*>(e);
        Type* to = resolveValueType(*c->type, sc.file, sc.env);
        ConstVal v = constEval(c->operand.get(), sc);
        Type* from = v.type;
        if (from == to)
            return v;
        Value probe = probeOf(v);
        if (conversionCost(probe, to) >= 0)
            return constConvert(v, to, e->loc);
        auto numeric = [](Type* t) { return t->isInt() || t->isChar() || t->isEnum() || t->isFloat(); };
        if (numeric(from) && numeric(to))
        {
            if (from->isEnum() && to->isFloat())
                err(e->loc, "cannot cast an enum to a floating point type");
            return constNumericConvert(v, to);
        }
        err(e->loc, "cannot cast '" + from->name + "' to '" + to->name + "'");
    }
    case ExprKind::SizeOf:
    {
        Type* t = resolveValueType(*static_cast<SizeOfExpr*>(e)->type, sc.file, sc.env);
        if (t->isVoid())
            err(e->loc, "sizeof(void) is not defined");
        return makeInt(types.i32, false, sizeOf(t));
    }
    default:
        return notConstant();
    }
    return ConstVal{};
}

// The value of a top-level constant (evaluated once; a constant that needs itself is an error).
ConstVal CodeGen::constEvalDecl(ConstDecl* c)
{
    ConstState& st = constCache[c];
    if (st.state == 2)
        return st.value;
    if (st.state == 1)
        err(c->loc, "constant '" + c->name + "' depends on itself");
    st.state = 1;
    try
    {
        Type* t = resolveValueType(*c->type, c->file, nullptr);
        if (!isConstantType(t))
            err(c->loc, "constants can only be numbers, bool, char, string or enum values");
        ConstScope sc{c->file, false, nullptr, "constant '" + c->name + "'", c->loc, nullptr};
        ConstVal v = constEval(c->init.get(), sc);
        // enumerators of imported C enums are written as integers
        st.value = constConvert(v, t, c->init->loc, c->file->isPrelude);
        st.state = 2;
        return st.value;
    }
    catch (...)
    {
        st.state = 0;
        throw;
    }
}

// The value of a member of the enum that is being declared: an integer constant that fits into the base type.
int64_t CodeGen::constEvalEnumMember(Expr* init, EnumInfo& ei, FileContext* file, const std::string& memberName, SourceLoc loc)
{
    ConstScope sc{file, false, &ei, "enum member '" + memberName + "'", loc, nullptr};
    ConstVal v = constEval(init, sc);
    if (v.kind != ConstVal::Int)
        err(loc, "the value of enum member '" + memberName + "' must be an integer constant");
    if (!fitsType(v, ei.base))
        err(loc, "enum value " + decimalOf(v) + " does not fit into " + ei.base->name);
    return (int64_t)patternOf(v, 64);
}
