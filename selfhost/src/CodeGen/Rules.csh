// Decisions of the language that the checker (selfhost/src/Check) and code generation share: the result type of an
// operator, whether a value can become text or be a condition, the common type of '?:'. Each function returns the
// result, or 0 and the message of the error; code generation fails with the message, the checker reports it and
// continues. With an operand of the unknown type (the checker's, see docs/semantic-pass.md) the result is unknown and
// nothing is reported.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;

bool AnyUnknown(Compiler cg, Value a, Value b)
{
    return cg.Types.IsUnknown(a.Type) || cg.Types.IsUnknown(b.Type);
}

// "" if a value of this type can become text ('+' with a string, interpolation), otherwise the message.
string TextConversionError(Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsUnknown(t) || types.IsString(t) || types.IsStringSlice(t) || types.IsBool(t) || types.IsChar(t) ||
        types.IsEnum(t) || types.IsInt(t) || types.IsFloat(t) || types.Kind(t) == TypeKind.Null)
        return "";
    if (types.IsStruct(t))
    {
        foreach (var c in MethodCandidates(cg, t, "ToString"))
        {
            var d = cg.Funcs.Get(c.Entry).Decl;
            if (!d.IsStatic && d.Params.Length == 0)
                return "";
        }
        return "cannot convert '" + types.Name(t) + "' to a string (give it a method 'string ToString()')";
    }
    return "cannot convert '" + types.Name(t) + "' to a string";
}

// Error<T> and Optional<T> are not conditions: "" or the message that says how to test them.
string AmbiguousConditionError(Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsError(t))
    {
        int inner = types.Elem(t);
        string succeeded = "";
        if (types.IsOptional(inner))
            succeeded = ", 'is " + types.Name(types.Elem(inner)) + " v' (succeeded with a value) or 'is " + types.Name(inner) +
                        " o' (succeeded)";
        else if (!types.IsVoid(inner))
            succeeded = " or 'is " + types.Name(inner) + " v' (succeeded)";
        return "'" + types.Name(t) + "' cannot be used as a condition; test it with 'is error e' (failed)" + succeeded;
    }
    if (types.IsOptional(t))
        return "'" + types.Name(t) + "' cannot be used as a condition; test it with 'is " + types.Name(types.Elem(t)) +
               " v' (has a value) or '== null' / '!= null'";
    return "";
}

// "" if a value of this type is a condition ('if', 'while', '&&', '?:'), otherwise the message.
string ConditionError(Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsBool(t) || types.IsUnknown(t))
        return "";
    string ambiguous = AmbiguousConditionError(cg, t);
    if (ambiguous.Length > 0)
        return ambiguous;
    return "a condition must be of type 'bool', not '" + types.Name(t) + "' (there is no implicit conversion to bool)";
}

// The result type of l op r for + - * / % & | ^ << >> (see EmitArithmetic), 0 with the message, or unknown.
int ArithmeticType(Compiler cg, BinOp op, Value l, Value r, ref string why)
{
    var types = cg.Types;
    if (AnyUnknown(cg, l, r))
        return types.Unknown;
    // string concatenation: the other operand may be anything that has a text
    if (op == BinOp.Add && (types.IsString(l.Type) || types.IsString(r.Type)))
    {
        why = TextConversionError(cg, l.Type);
        if (why.Length == 0)
            why = TextConversionError(cg, r.Type);
        return why.Length > 0 ? 0 : types.String;
    }
    if (types.IsPointer(l.Type) || types.IsPointer(r.Type))
        return types.Unknown; // pointer arithmetic: checked by code generation
    if (l.Type == r.Type && (op == BinOp.BitAnd || op == BinOp.BitOr || op == BinOp.BitXor) && (types.IsEnum(l.Type) || types.IsBool(l.Type)))
        return l.Type;
    if (!types.IsNumeric(l.Type) || !types.IsNumeric(r.Type))
    {
        why = "operator '" + BinOpText(op) + "' cannot be applied to '" + types.Name(l.Type) + "' and '" + types.Name(r.Type) + "'";
        return 0;
    }
    if (op == BinOp.Shl || op == BinOp.Shr)
    {
        if (!types.IsIntegral(l.Type) || !types.IsIntegral(r.Type))
        {
            why = "shift operators require integer operands";
            return 0;
        }
        int st = PromoteTypesOrError(cg, l.Type, l.Type, ref why);
        if (st == 0)
            return 0;
        why = ConversionError(cg, l.HasLit ? AdaptLiteral(cg, l, st) : l, st);
        return why.Length > 0 ? 0 : st;
    }
    Value lv = l;
    Value rv = r;
    if (l.HasLit && !r.HasLit)
        lv = AdaptLiteral(cg, l, r.Type);
    else if (r.HasLit && !l.HasLit)
        rv = AdaptLiteral(cg, r, l.Type);
    int t = PromoteTypesOrError(cg, lv.Type, rv.Type, ref why);
    if (t == 0)
        return 0;
    why = ConversionError(cg, lv, t);
    if (why.Length == 0)
        why = ConversionError(cg, rv, t);
    if (why.Length > 0)
        return 0;
    if (types.IsFloat(t) && op != BinOp.Add && op != BinOp.Sub && op != BinOp.Mul && op != BinOp.Div && op != BinOp.Rem)
    {
        why = "bit operations are not defined for floating point values";
        return 0;
    }
    return t;
}

// The type of l op r for == != < > <= >= (bool, see EmitCompare), 0 with the message, or unknown.
int CompareType(Compiler cg, BinOp op, Value l, Value r, ref string why)
{
    var types = cg.Types;
    if (AnyUnknown(cg, l, r) || types.Kind(l.Type) == TypeKind.MethodGroup || types.Kind(r.Type) == TypeKind.MethodGroup)
        return types.Unknown;
    bool isEq = op == BinOp.Eq || op == BinOp.Ne;
    if (types.Kind(l.Type) == TypeKind.Null || types.Kind(r.Type) == TypeKind.Null)
    {
        if (!isEq)
        {
            why = "null can only be compared with '==' and '!='";
            return 0;
        }
        var k = types.Kind(types.Kind(l.Type) == TypeKind.Null ? r.Type : l.Type);
        if (k == TypeKind.Pointer || k == TypeKind.String || k == TypeKind.Array || k == TypeKind.CFunction || k == TypeKind.Function ||
            k == TypeKind.SharedPtr || k == TypeKind.Optional || k == TypeKind.Null)
            return types.Bool;
        why = "type '" + types.Name(types.Kind(l.Type) == TypeKind.Null ? r.Type : l.Type) + "' cannot be compared with null";
        return 0;
    }
    if ((types.IsStringSlice(l.Type) || types.IsStringSlice(r.Type)) &&
        (types.IsString(l.Type) || types.IsStringSlice(l.Type)) && (types.IsString(r.Type) || types.IsStringSlice(r.Type)))
    {
        if (!isEq)
        {
            why = "string slices can only be compared with '==' and '!='";
            return 0;
        }
        return types.Bool;
    }
    if (types.IsString(l.Type) && types.IsString(r.Type))
    {
        if (!isEq)
        {
            why = "strings can only be compared with '==' and '!='";
            return 0;
        }
        return types.Bool;
    }
    Value lv = l;
    Value rv = r;
    if (l.HasLit && !r.HasLit)
        lv = AdaptLiteral(cg, l, r.Type);
    else if (r.HasLit && !l.HasLit)
        rv = AdaptLiteral(cg, r, l.Type);
    if (lv.Type == rv.Type && (types.IsBool(lv.Type) || types.IsEnum(lv.Type) || types.IsPointer(lv.Type) || types.IsFunction(lv.Type)))
    {
        if ((types.IsBool(lv.Type) || types.IsFunction(lv.Type)) && !isEq)
        {
            why = types.IsBool(lv.Type) ? "bool values can only be compared with '==' and '!='" : "function values can only be compared with '==' and '!='";
            return 0;
        }
        return types.Bool;
    }
    if (IsErrorEnum(cg, lv.Type) && types.IsNumeric(rv.Type))
        lv = Rvalue(types.I32, "", false);
    if (IsErrorEnum(cg, rv.Type) && types.IsNumeric(lv.Type))
        rv = Rvalue(types.I32, "", false);
    if (!types.IsNumeric(lv.Type) || !types.IsNumeric(rv.Type))
    {
        why = "cannot compare '" + types.Name(lv.Type) + "' with '" + types.Name(rv.Type) + "'";
        return 0;
    }
    int t = PromoteTypesOrError(cg, lv.Type, rv.Type, ref why);
    if (t == 0)
        return 0;
    why = ConversionError(cg, lv, t);
    if (why.Length == 0)
        why = ConversionError(cg, rv, t);
    return why.Length > 0 ? 0 : types.Bool;
}

// -literal: a literal again (it still adapts to the type it is used with).
Value NegateLiteral(Compiler cg, Value v)
{
    var types = cg.Types;
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

// The value of -v, +v, !v, ~v as far as its type goes (see EmitUnary): Type 0 with the message on an error, unknown for
// the pointer operators.
Value UnaryResult(Compiler cg, UnOp op, Value v, ref string why)
{
    var types = cg.Types;
    if (types.IsUnknown(v.Type) || op == UnOp.Deref || op == UnOp.AddrOf)
        return Rvalue(types.Unknown, "", false);
    switch (op)
    {
    case UnOp.Neg:
    case UnOp.Plus:
    {
        if (v.HasLit && op == UnOp.Neg)
            return NegateLiteral(cg, v);
        if (!types.IsNumeric(v.Type))
        {
            why = "unary '-' cannot be applied to '" + types.Name(v.Type) + "'";
            return Value { };
        }
        int pt = types.IsFloat(v.Type) ? v.Type : PromoteTypesOrError(cg, v.Type, v.Type, ref why);
        if (pt == 0)
            return Value { };
        why = ConversionError(cg, v, pt);
        if (why.Length > 0)
            return Value { };
        if (op == UnOp.Neg && !types.IsFloat(pt) && !types.IsSigned(pt))
        {
            why = "unary '-' cannot be applied to unsigned type '" + types.Name(pt) + "'";
            return Value { };
        }
        return Rvalue(pt, "", false);
    }
    case UnOp.Not:
        if (types.IsBool(v.Type))
            return Rvalue(types.Bool, "", false);
        why = AmbiguousConditionError(cg, v.Type);
        if (why.Length == 0)
            why = "operator '!' cannot be applied to '" + types.Name(v.Type) + "'";
        return Value { };
    default: // BitNot
    {
        if (types.IsEnum(v.Type))
            return Rvalue(v.Type, "", false);
        if (!types.IsIntegral(v.Type))
        {
            why = "operator '~' cannot be applied to '" + types.Name(v.Type) + "'";
            return Value { };
        }
        int pt = PromoteTypesOrError(cg, v.Type, v.Type, ref why);
        return pt == 0 ? Value { } : Rvalue(pt, "", false);
    }
    }
}

// The type of 'c ? a : b' from the types of its branches (see EmitConditional), 0 with the message, or unknown.
int ConditionalType(Compiler cg, Value a, Value b, ref string why)
{
    var types = cg.Types;
    if (AnyUnknown(cg, a, b))
        return types.Unknown;
    int t;
    if (a.Type == b.Type)
        t = a.Type;
    else if (ConversionCost(cg, a, b.Type) >= 0 && (ConversionCost(cg, b, a.Type) < 0 || a.HasLit))
        t = b.Type;
    else if (ConversionCost(cg, b, a.Type) >= 0)
        t = a.Type;
    else
    {
        why = "the branches of '?:' have incompatible types '" + types.Name(a.Type) + "' and '" + types.Name(b.Type) + "'";
        return 0;
    }
    if (types.Kind(t) == TypeKind.Null)
    {
        why = "cannot infer the type of a conditional expression with only null";
        return 0;
    }
    if (types.IsVoid(t))
    {
        why = "conditional branches cannot be void";
        return 0;
    }
    return t;
}

// The type of 'var name = init' (see EmitVarDecl; collection expressions are settled before), 0 with the message, or
// unknown.
int VarTypeFromInit(Compiler cg, Value init, string name, ref string why)
{
    var types = cg.Types;
    int t = init.Type;
    if (types.IsUnknown(t) || types.Kind(t) == TypeKind.Collection)
        return types.Unknown;
    if (types.Kind(t) == TypeKind.MethodGroup)
    {
        // 'var f = Square;' has the function type of Square if the name has a single meaning.
        t = GroupFunctionType(cg, init);
        if (t == 0)
        {
            why = "cannot infer the type of '" + name + "' from the function name '" + init.GroupName +
                  "' (it is overloaded, generic or not a plain function); declare an Action/Func type";
            return 0;
        }
    }
    if (IsInterfaceType(cg, t))
    {
        why = "'" + name + "' cannot hold the interface parameter: an interface is only a 'ref'/'const ref' parameter";
        return 0;
    }
    if (types.Kind(t) == TypeKind.Lambda)
    {
        why = "cannot infer the type of '" + name + "' from a lambda; declare it with its Action/Func type";
        return 0;
    }
    var k = types.Kind(t);
    if (k == TypeKind.Null || k == TypeKind.ErrorLit || k == TypeKind.Void)
    {
        why = "cannot infer the type of '" + name + "' from '" + types.Name(t) + "'";
        return 0;
    }
    return t;
}
