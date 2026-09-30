// Sizes and alignments of IR types for the 68000 backend: the layout of the AmigaOS compilers (and of GCC on m68k):
// one-byte values are byte aligned, everything larger is aligned to two bytes. It matches what the front end computes
// for the m68k backend (Emit/Target.csh), so sizeof, unions and slices agree with the generated code.

namespace CShift.M68k;

using System;

struct Layouts
{
    IrTypes Types;
    Dictionary<int, int> Sizes;
    Dictionary<int, int> Aligns;

    static Layouts Create(IrTypes types)
    {
        return Layouts { Types = types, Sizes = Dictionary<int, int>.Create(), Aligns = Dictionary<int, int>.Create() };
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
        int a = Align(t);
        int s = Size(t);
        return (s + a - 1) / a * a;
    }

    // The offset of field i of a struct.
    int FieldOffset(int t, int index)
    {
        var info = Types.Info(t);
        int pos = 0;
        for (var i = 0; i < index; i += 1)
        {
            int f = info.Fields[i];
            pos = AlignTo(pos, Align(f)) + Size(f);
        }
        return AlignTo(pos, Align(info.Fields[index]));
    }

    void Compute(int t)
    {
        var info = Types.Info(t);
        int size = 0;
        int align = 1;
        switch (info.Kind)
        {
        case IrKind.Int:
            size = info.Bits <= 8 ? 1 : info.Bits / 8;
            align = size == 1 ? 1 : 2;
            break;
        case IrKind.Ptr:
        case IrKind.Float:
            size = 4;
            align = 2;
            break;
        case IrKind.Double:
            size = 8;
            align = 2;
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
                pos = AlignTo(pos, fa) + Size(f);
                if (fa > align)
                    align = fa;
            }
            size = AlignTo(pos, align);
            break;
        }
        default:
            break;
        }
        Sizes.Set(t, size);
        Aligns.Set(t, align);
    }
}

int AlignTo(int value, int align)
{
    if (align <= 1)
        return value;
    return (value + align - 1) / align * align;
}
