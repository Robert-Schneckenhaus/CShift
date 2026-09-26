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
    bool IsError;       // an error enum ('error E { ... }'): the codes of Error<T, E>
}

// An error enum: its values are error codes; it converts implicitly to int.
bool IsErrorEnum(Compiler cg, int t)
{
    return cg.Types.IsEnum(t) && GetEnumInfo(cg, t).IsError;
}

EnumInfo GetEnumInfo(Compiler cg, int enumType)
{
    return cg.EnumInfos.Get(cg.Types.Decl(enumType));
}

int FindEnumMember(EnumInfo info, string name)
{
    for (var i = 0; i < info.Names.Length; i += 1)
    {
        if (info.Names[i] == name)
            return i;
    }
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

    int b = decl.IsError ? types.I32 : ResolveType(cg, decl.Base.Id, ee.File, NoEnv());
    if (!types.IsInt(b))
        Fail(cg, cg.Tree.GetType(decl.Base).Loc, "enum base type must be an integer type");

    int t = types.Add(TypeKind.Enum, key, types.Bits(b), types.IsSigned(b));
    var info = EnumInfo { Entry = entry, Name = key, Type = t, Base = b, IsError = decl.IsError };
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

    // error codes count from 1: code 0 is "no specific code" (error("text"), a default result)
    int64 next = decl.IsError ? 1 : 0;
    foreach (var m in decl.Members)
    {
        // members may refer to the members before them
        var known = EnumInfo { Names = names.ToArray(), Values = values.ToArray(), Base = b };
        int64 v = m.Value.IsNull() ? next : ConstEvalEnumMember(cg, m.Value, known, ee.File, m.Name, m.Loc);
        if (decl.IsError && v == 0)
            Fail(cg, m.Loc, "error code '" + m.Name + "' cannot be 0: code 0 means \"no specific code\" (error codes count from 1)");
        if (m.Value.IsNull() && !FitsInt(v, types.Bits(b), types.IsSigned(b)))
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
