// Sizes and alignments of types, and the layout of structs imported from C headers.
//
// The IR is written as text, so there is no LLVM data layout to ask: sizes follow the rules of the 64-bit targets that
// CShift supports (pointers have 8 bytes, every scalar is aligned to its size, structs are padded like in C).

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
        int64 bytes = (int64)(types.Bits(t) / 8);
        return SizeAlign { Size = bytes, Align = bytes };
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
    default:
        return SizeAlign { Size = 8, Align = 8 }; // pointers, strings, arrays, function values
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
            Fail(cg, f.Loc, "field '" + f.Name + "' cannot have type 'void'");
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
