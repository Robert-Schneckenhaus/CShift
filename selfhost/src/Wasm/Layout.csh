// Sizes and alignments of IR types on wasm32: natural alignment (i16 2, i32/ptr/float 4, i64/double 8), the layout of
// clang's wasm32 data layout, which the front end computes for a wasm32 triple too (Emit/Target.csh).

namespace CShift.Wasm;

using System;
using CShift.M68k;

struct WasmLayouts
{
    IrTypes Types;
    Dictionary<int, int> Sizes;
    Dictionary<int, int> Aligns;

    static WasmLayouts Create(IrTypes types)
    {
        return WasmLayouts { Types = types, Sizes = Dictionary<int, int>.Create(), Aligns = Dictionary<int, int>.Create() };
    }

    int Size(int t)
    {
        var found = Sizes.TryGet(t);
        if (found is int s)
            return s;
        Compute(t);
        return Sizes.Get(t);
    }

    int Align(int t)
    {
        var found = Aligns.TryGet(t);
        if (found is int a)
            return a;
        Compute(t);
        return Aligns.Get(t);
    }

    // The distance between two elements of an array of t.
    int Stride(int t)
    {
        return WasmAlignTo(Size(t), Align(t));
    }

    // The offset of field i of a struct (or element i of an array).
    int FieldOffset(int t, int index)
    {
        var info = Types.Info(t);
        if (info.Kind == IrKind.Array)
            return index * Stride(info.Elem);
        int pos = 0;
        for (var i = 0; i < index; i += 1)
        {
            int f = info.Fields[i];
            pos = WasmAlignTo(pos, Align(f)) + Size(f);
        }
        return WasmAlignTo(pos, Align(info.Fields[index]));
    }

    void Compute(int t)
    {
        var info = Types.Info(t);
        int size = 0;
        int align = 1;
        switch (info.Kind)
        {
        case IrKind.Int:
            size = info.Bits <= 8 ? 1 : (info.Bits + 7) / 8;
            align = size;
            break;
        case IrKind.Ptr:
        case IrKind.Float:
            size = 4;
            align = 4;
            break;
        case IrKind.Double:
            size = 8;
            align = 8;
            break;
        case IrKind.Array:
            size = info.Count * Stride(info.Elem);
            align = Align(info.Elem);
            break;
        case IrKind.Struct:
        {
            int pos = 0;
            foreach (var f in info.Fields)
            {
                int fa = Align(f);
                pos = WasmAlignTo(pos, fa) + Size(f);
                if (fa > align)
                    align = fa;
            }
            size = WasmAlignTo(pos, align);
            break;
        }
        default:
            break;
        }
        Sizes.Set(t, size);
        Aligns.Set(t, align);
    }
}

int WasmAlignTo(int value, int align)
{
    if (align <= 1)
        return value;
    return (value + align - 1) / align * align;
}
