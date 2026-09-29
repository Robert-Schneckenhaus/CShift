// Sizes and alignments of types, and the layout of structs imported from C headers.
//
// The IR is written as text, so there is no LLVM data layout to ask: sizes follow the target's rules (Emit/Target.csh:
// the size of pointers and the alignment of the scalars; structs are padded like in C).

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

struct SizeAlign
{
    int64 Size;
    int64 Align;
}

int64 AlignUp(int64 value, int64 align)
{
    if (align <= 1)
        return value;
    return (value + align - 1) / align * align;
}

// The size and alignment of members placed one after the other (like the fields of a C struct).
SizeAlign AggregateLayout(Compiler cg, int[] members)
{
    int64 pos = 0;
    int64 maxAlign = 1;
    foreach (var m in members)
    {
        var l = TypeLayout(cg, m);
        pos = AlignUp(pos, l.Align) + l.Size;
        if (l.Align > maxAlign)
            maxAlign = l.Align;
    }
    return SizeAlign { Size = AlignUp(pos, maxAlign), Align = maxAlign };
}

// ---------------------------------------------------------------------------
// Sizes, lengths and indexes: i64, or i32 on a 32-bit target
// ---------------------------------------------------------------------------

// The LLVM type of sizes, lengths and indexes (the length in a block header and in a slice, array indexes).
string SizeIr(Compiler cg)
{
    return cg.Ir.Target.SizeIr;
}

// The offset of the elements in a string or array block (after the refcount and the length).
string HeaderSize(Compiler cg)
{
    return cg.Ir.Target.HeaderBytes().ToString();
}

// A size as an int32 (Length).
string SizeToI32(Compiler cg, string v)
{
    return SizeIr(cg) == "i32" ? v : cg.Ir.Cast("trunc", SizeIr(cg), v, "i32");
}

// An int32 as a size.
string I32ToSize(Compiler cg, string v, bool isSigned)
{
    return SizeIr(cg) == "i32" ? v : cg.Ir.Cast(isSigned ? "sext" : "zext", "i32", v, SizeIr(cg));
}

// A size as an int64 (the index and length in a panic message, pointer differences).
string SizeToI64(Compiler cg, string v, bool isSigned)
{
    return SizeIr(cg) == "i64" ? v : cg.Ir.Cast(isSigned ? "sext" : "zext", SizeIr(cg), v, "i64");
}

// An integer as a size (an index, a count): converted like to int64/uint64 (nint/nuint on a 32-bit target). On a 32-bit
// target a 64-bit value that does not fit becomes -1 (all bits set), which every bounds check rejects.
string SizeIndex(Compiler cg, string v, int type)
{
    var types = cg.Types;
    var ir = cg.Ir;
    bool isSigned = types.IsInt(type) && types.IsSigned(type);
    if (SizeIr(cg) == "i64")
        return NumericConvert(cg, v, type, isSigned ? types.I64 : types.U64);
    if (types.Bits(type) <= 32)
        return NumericConvert(cg, v, type, isSigned ? types.Nint : types.Nuint);
    string fits = isSigned
        ? ir.Bin("and", "i1", ir.ICmp("sge", "i64", v, "-2147483648"), ir.ICmp("sle", "i64", v, "2147483647"))
        : ir.ICmp("ule", "i64", v, "4294967295");
    return ir.Select(fits, "i32", ir.Cast("trunc", "i64", v, "i32"), "-1");
}

// A text of IR for the target (see Sized in Runtime.csh: $S, $P, $H, $I).
string SizedText(Compiler cg, string text)
{
    return Sized(text, cg.Ir);
}

SizeAlign PointerLayout(Compiler cg, int count)
{
    return SizeAlign { Size = (int64)(count * cg.Ir.Target.PtrBytes), Align = (int64)cg.Ir.Target.PtrAlign };
}

SizeAlign TypeLayout(Compiler cg, int t)
{
    var types = cg.Types;
    switch (types.Kind(t))
    {
    case TypeKind.Void: return SizeAlign { Size = 0, Align = 1 };
    case TypeKind.Bool: return SizeAlign { Size = 1, Align = 1 };
    case TypeKind.Int:
    case TypeKind.Char:
    case TypeKind.Enum:
    case TypeKind.Float:
    {
        int bytes = types.Bits(t) / 8;
        return SizeAlign { Size = (int64)bytes, Align = (int64)cg.Ir.Target.ScalarAlign(bytes, types.IsFloat(t)) };
    }
    case TypeKind.Struct:
    {
        var si = GetStructInfo(cg, t);
        if (si.LayoutInProgress)
            Fail(cg, cg.Structs.Get(si.Entry).Decl.Loc, "struct '" + si.Name + "' contains itself by value");
        var decl = cg.Structs.Get(si.Entry).Decl;
        if (decl.ExplicitLayout)
            return SizeAlign { Size = (int64)decl.LayoutSize, Align = decl.LayoutAlign > 0 ? (int64)decl.LayoutAlign : 1 };
        var members = List<int>.Create();
        if (si.Base != 0)
            members.Add(si.Base);
        foreach (var f in si.Fields)
            members.Add(f.Type);
        return AggregateLayout(cg, members.ToArray());
    }
    case TypeKind.Error:
    {
        int elem = types.Elem(t);
        var members = List<int>.Create();
        members.Add(types.Bool);
        if (!types.IsVoid(elem))
            members.Add(elem);
        members.Add(types.String);
        members.Add(types.I32);
        return AggregateLayout(cg, members.ToArray());
    }
    case TypeKind.Optional:
        return AggregateLayout(cg, new int[] { types.Bool, types.Elem(t) });
    case TypeKind.ErrorLit:
        return AggregateLayout(cg, new int[] { types.String, types.I32 });
    case TypeKind.Function:
    case TypeKind.Interface:
        return PointerLayout(cg, 2); // { ptr, ptr }
    case TypeKind.Slice:
    case TypeKind.ReadOnlySlice:
    case TypeKind.StringSlice:
        return PointerLayout(cg, 3); // { ptr, ptr, size }
    case TypeKind.Fixed:
    {
        var e = TypeLayout(cg, types.Elem(t));
        return SizeAlign { Size = e.Size * (int64)types.Count(t), Align = e.Align };
    }
    case TypeKind.Union:
    {
        var ui = GetUnionInfo(cg, t);
        return SizeAlign { Size = ui.Size, Align = ui.Align };
    }
    default:
        return PointerLayout(cg, 1); // pointers, strings, arrays, function values
    }
}

// The layout of a struct imported from a C header: the fields sit at the offsets the C compiler chose; everything
// else (arrays, bit fields, union members, padding) is filler. Returns the elements of the LLVM struct.
void LayoutExplicitStruct(Compiler cg, int index)
{
    var types = cg.Types;
    var si = cg.StructInfos.Get(index);
    var se = cg.Structs.Get(si.Entry);
    var decl = se.Decl;
    si.Opaque = decl.Opaque;

    // the fields ordered by offset
    int count = decl.Fields.Length;
    var order = new int[count];
    for (var i = 0; i < count; i += 1)
        order[i] = i;
    for (var i = 1; i < count; i += 1)
    {
        int v = order[i];
        int k = i - 1;
        while (k >= 0 && decl.Fields[order[k]].Offset > decl.Fields[v].Offset)
        {
            order[k + 1] = order[k];
            k -= 1;
        }
        order[k + 1] = v;
    }

    var elems = List<string>.Create();
    var fields = List<FieldInfo>.Create();
    var placedTypes = new int[count];
    int64 maxAlign = 1;
    for (var i = 0; i < count; i += 1)
    {
        var f = decl.Fields[order[i]];
        int ft = ResolveValueType(cg, f.Type.Id, se.File, si.Env);
        if (types.IsVoid(ft))
            ft = RecoverType(cg, f.Loc, "field '" + f.Name + "' cannot have type 'void'");
        if (types.IsFunction(ft))
            ft = types.CFunctionOf(ft); // C stores a plain function pointer
        var l = TypeLayout(cg, ft);
        if (f.Offset % l.Align != 0)
            Fail(cg, decl.Loc, "struct '" + decl.Name + "': field '" + f.Name + "' is not naturally aligned (packed structs are not supported)");
        if (l.Align > maxAlign)
            maxAlign = l.Align;
        placedTypes[i] = ft;
    }

    // an alignment that the fields do not imply (alignas, unions) comes from a zero-sized array in front
    if ((int64)decl.LayoutAlign > maxAlign)
        elems.Add("[0 x i" + ((int64)decl.LayoutAlign * 8).ToString() + "]");

    int64 pos = 0;
    for (var i = 0; i < count; i += 1)
    {
        var f = decl.Fields[order[i]];
        int64 offset = f.Offset;
        if (offset < pos)
            Fail(cg, decl.Loc, "struct '" + decl.Name + "': field '" + f.Name + "' overlaps the previous field");
        if (offset > pos)
            elems.Add("[" + (offset - pos).ToString() + " x i8]");
        fields.Add(FieldInfo { Name = f.Name, Type = placedTypes[i], Index = elems.Count(), IsPrivate = false });
        elems.Add(LlvmType(cg, placedTypes[i]));
        pos = offset + TypeLayout(cg, placedTypes[i]).Size;
    }
    if (pos > (int64)decl.LayoutSize)
        Fail(cg, decl.Loc, "struct '" + decl.Name + "': the fields are larger than the struct");
    if (pos < (int64)decl.LayoutSize)
        elems.Add("[" + ((int64)decl.LayoutSize - pos).ToString() + " x i8]");

    si.Fields = fields.ToArray();
    si.LayoutInProgress = false;
    cg.StructInfos.Set(index, si);

    var body = StringBuilder.Create();
    for (var i = 0; i < elems.Count(); i += 1)
    {
        if (i > 0)
            body.Append(", ");
        body.Append(elems.Get(i));
    }
    cg.Ir.Globals.Append(si.IrName + " = type { " + body.ToString() + " }\n");
}
