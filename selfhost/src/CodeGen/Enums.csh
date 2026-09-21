// Enums: the type, the values of the members and constant integer expressions (port of CodeGen::getEnumType and
// CodeGen::constEvalInt). An enum value is an integer of the base type of the enum.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

struct EnumInfo
{
    int Entry;          // index in Compiler.Enums
    string Name;
    int Type;
    int Base;           // integer type of the values
    string[] Names;
    int64[] Values;
}

EnumInfo GetEnumInfo(Compiler cg, int enumType)
{
    return cg.EnumInfos.Get(cg.Types.Decl(enumType));
}

int FindEnumMember(EnumInfo info, string name)
{
    for (var i = 0; i < info.Names.Length; i += 1)
        if (info.Names[i] == name)
            return i;
    return -1;
}

bool FitsInt(int64 v, int bits, bool isSigned)
{
    if (bits >= 64)
        return isSigned || v >= 0;
    int64 limit = (int64)1 << (isSigned ? bits - 1 : bits);
    if (isSigned)
        return v >= -limit && v < limit;
    return v >= 0 && v < limit;
}

int GetEnumType(Compiler cg, int entry)
{
    var types = cg.Types;
    var ee = cg.Enums.Get(entry);
    var decl = ee.Decl;
    string key = Qualified(cg, ee.File, decl.Name);
    var existing = cg.EnumTypes.TryGet(key);
    if (existing is int found)
        return found;

    int b = ResolveType(cg, decl.Base.Id, ee.File, NoEnv());
    if (!types.IsInt(b))
        Fail(cg, cg.Tree.GetType(decl.Base).Loc, "enum base type must be an integer type");

    int t = types.Add(TypeKind.Enum, key, types.Bits(b), types.IsSigned(b));
    var info = EnumInfo { Entry = entry, Name = key, Type = t, Base = b };
    var ti = types.Info(t);
    ti.Elem = b;
    ti.Decl = cg.EnumInfos.Count();
    types.SetInfo(t, ti);
    cg.EnumTypes.Set(key, t);

    var names = List<string>.Create();
    var values = List<int64>.Create();
    info.Names = names.ToArray();
    info.Values = values.ToArray();
    cg.EnumInfos.Add(info);
    int index = cg.EnumInfos.Count() - 1;

    int64 next = 0;
    foreach (var m in decl.Members)
    {
        // members may refer to the members before them
        var known = EnumInfo { Names = names.ToArray(), Values = values.ToArray() };
        int64 v = m.Value.IsNull() ? next : ConstEvalInt(cg, m.Value, known, m.Loc);
        if (!FitsInt(v, types.Bits(b), types.IsSigned(b)))
            Fail(cg, m.Loc, "enum value " + v.ToString() + " does not fit into " + types.Name(b));
        if (FindEnumMember(known, m.Name) >= 0)
            Fail(cg, m.Loc, "enum member '" + m.Name + "' is declared twice");
        names.Add(m.Name);
        values.Add(v);
        next = v + 1;
    }
    info.Names = names.ToArray();
    info.Values = values.ToArray();
    cg.EnumInfos.Set(index, info);
    return t;
}

// The value of a constant integer expression: literals, operators and the members of the enum that is being declared.
int64 ConstEvalInt(Compiler cg, Expr e, EnumInfo current, SourceLoc loc)
{
    var tree = cg.Tree;
    switch (e.Kind)
    {
    case ExprKind.IntLit:
        return (int64)tree.GetIntLit(e).Value;
    case ExprKind.CharLit:
        return (int64)tree.GetCharLit(e).Value;
    case ExprKind.Unary:
    {
        var u = tree.GetUnary(e);
        int64 v = ConstEvalInt(cg, u.Operand, current, loc);
        if (u.Op == UnOp.Neg)
            return -v;
        if (u.Op == UnOp.Plus)
            return v;
        if (u.Op == UnOp.BitNot)
            return ~v;
        break;
    }
    case ExprKind.Binary:
    {
        var b = tree.GetBinary(e);
        int64 l = ConstEvalInt(cg, b.Lhs, current, loc);
        int64 r = ConstEvalInt(cg, b.Rhs, current, loc);
        switch (b.Op)
        {
        case BinOp.Add: return l + r;
        case BinOp.Sub: return l - r;
        case BinOp.Mul: return l * r;
        case BinOp.Div:
            if (r == 0)
                Fail(cg, e.Loc, "division by zero in constant expression");
            return l / r;
        case BinOp.Rem:
            if (r == 0)
                Fail(cg, e.Loc, "division by zero in constant expression");
            return l % r;
        case BinOp.BitAnd: return l & r;
        case BinOp.BitOr: return l | r;
        case BinOp.BitXor: return l ^ r;
        case BinOp.Shl: return l << (int)r;
        case BinOp.Shr: return l >> (int)r;
        default: break;
        }
        break;
    }
    case ExprKind.Name:
    {
        int i = FindEnumMember(current, tree.GetName(e).Name);
        if (i >= 0)
            return current.Values[i];
        break;
    }
    default: break;
    }
    Fail(cg, e.Loc.Line > 0 ? e.Loc : loc, "expected a constant integer expression");
    return 0;
}
