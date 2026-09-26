// Slices: Slice<T> (a view of part of an array) and StringSlice (a view of part of a string, read-only).
//
// A slice is { ptr owner, ptr data, i64 length }: the block that owns the elements (an array or a string, whose
// reference the slice holds), the first element and the number of elements. Creating a slice copies nothing; the view
// keeps the whole block alive. a[i..j], a[..j], a[i..], a[..] slice arrays, strings and slices; ^n counts from the end.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// The type of the block a slice refers to: T[] for Slice<T>, string for StringSlice.
int SliceOwnerType(Compiler cg, int sliceType)
{
    var types = cg.Types;
    return types.IsStringSlice(sliceType) ? types.String : types.ArrayOf(types.Elem(sliceType));
}

// The element type of an array, a string or a slice (char for strings).
int SliceElemType(Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsString(t) || types.IsStringSlice(t))
        return types.Char;
    return types.Elem(t);
}

// The slice type that slicing a value of type t gives, or 0 if t cannot be sliced.
int SliceTypeOf(Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsString(t) || types.IsStringSlice(t))
        return types.StringSlice;
    if (types.IsArray(t))
        return types.SliceOf(types.Elem(t));
    if (types.Kind(t) == TypeKind.Slice)
        return t;
    return 0;
}

// The parts of an array, a string or a slice value: its owning block, its first element and its length.
struct SliceParts
{
    string Owner;
    string Data;
    string Length;
}

SliceParts PartsOf(Compiler cg, Value v)
{
    var types = cg.Types;
    var ir = cg.Ir;
    if (types.IsSlice(v.Type))
    {
        string ty = LlvmType(cg, v.Type);
        return SliceParts { Owner = ir.ExtractValue(ty, v.V, "0"), Data = ir.ExtractValue(ty, v.V, "1"), Length = ir.ExtractValue(ty, v.V, "2") };
    }
    return SliceParts { Owner = v.V, Data = DataPtr(cg, v.V), Length = ArrayLength(cg, v.V) };
}

// A new slice value (the owner is retained: the slice is an owned temporary).
Value MakeSlice(Compiler cg, int sliceType, SliceParts p)
{
    var ir = cg.Ir;
    EmitRetain(cg, SliceOwnerType(cg, sliceType), p.Owner);
    string ty = LlvmType(cg, sliceType);
    string agg = ir.InsertValue(ty, "zeroinitializer", "ptr", p.Owner, "0");
    agg = ir.InsertValue(ty, agg, "ptr", p.Data, "1");
    agg = ir.InsertValue(ty, agg, "i64", p.Length, "2");
    return Rvalue(sliceType, agg, true);
}

// An array or a string as a slice of all its elements (the implicit conversion string -> StringSlice, T[] -> Slice<T>).
Value ToSlice(Compiler cg, Value v, int sliceType)
{
    Value r = ToRValue(cg, v);
    HoldTemp(cg, r);
    return MakeSlice(cg, sliceType, PartsOf(cg, r));
}

// An index for a[i] or a range bound: i64, counted from the end for ^n.
string SliceBound(Compiler cg, Expr e, bool fromEnd, string length)
{
    var types = cg.Types;
    Value v = EmitRValue(cg, e);
    if (!types.IsIntegral(v.Type))
        Fail(cg, e.Loc, "an index must be an integer, not '" + types.Name(v.Type) + "'");
    bool isSigned = types.IsInt(v.Type) && types.IsSigned(v.Type);
    string i64v = NumericConvert(cg, v.V, v.Type, isSigned ? types.I64 : types.U64);
    return fromEnd ? cg.Ir.Bin("sub", "i64", length, i64v) : i64v;
}

// a[start..end]
Value EmitSlice(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetSlice(e);
    Value obj = ToRValue(cg, EmitRValue(cg, n.Object));
    int sliceType = SliceTypeOf(cg, obj.Type);
    if (sliceType == 0)
        Fail(cg, e.Loc, "cannot slice a value of type '" + types.Name(obj.Type) + "' (only arrays, strings and slices)");
    HoldTemp(cg, obj);
    var parts = PartsOf(cg, obj);
    string start = n.Start.IsNull() ? "0" : SliceBound(cg, n.Start, n.StartFromEnd, parts.Length);
    string end = n.End.IsNull() ? parts.Length : SliceBound(cg, n.End, n.EndFromEnd, parts.Length);
    // 0 <= start <= end <= length
    string bad = ir.Bin("or", "i1", ir.ICmp("slt", "i64", start, "0"), ir.ICmp("sgt", "i64", start, end));
    bad = ir.Bin("or", "i1", bad, ir.ICmp("sgt", "i64", end, parts.Length));
    EmitPanicIf(cg, bad, "slice range out of bounds");
    int elem = SliceElemType(cg, sliceType);
    var result = SliceParts { Owner = parts.Owner, Length = ir.Bin("sub", "i64", end, start) };
    result.Data = ir.Gep(LlvmType(cg, elem), parts.Data, "i64 " + start);
    return MakeSlice(cg, sliceType, result);
}

// s[i] on a slice: bounds-checked; an element of a Slice<T> can be assigned (it is the array's element).
Value EmitSliceElement(Compiler cg, Value obj, Expr index, bool fromEnd, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value s = ToRValue(cg, obj);
    HoldTemp(cg, s);
    var parts = PartsOf(cg, s);
    string i = SliceBound(cg, index, fromEnd, parts.Length);
    EmitPanicIf(cg, ir.ICmp("uge", "i64", i, parts.Length), "slice index out of range");
    int elem = SliceElemType(cg, s.Type);
    string addr = ir.Gep(LlvmType(cg, elem), parts.Data, "i64 " + i);
    if (types.IsStringSlice(s.Type))
        return Rvalue(types.Char, ir.Load("i8", addr), false); // strings are immutable
    return Lvalue(elem, addr, false);
}

// The position of a slice's first element in its owner block (for copying out of it).
string SliceOffset(Compiler cg, int sliceType, SliceParts p)
{
    var ir = cg.Ir;
    string first = ir.Cast("ptrtoint", "ptr", DataPtr(cg, p.Owner), "i64");
    string data = ir.Cast("ptrtoint", "ptr", p.Data, "i64");
    string bytes = ir.Bin("sub", "i64", data, first);
    int64 size = TypeLayout(cg, SliceElemType(cg, sliceType)).Size;
    string elements = size == 1 ? bytes : ir.Bin("sdiv exact", "i64", bytes, size.ToString());
    // an empty slice without an owner (default, null) has no data pointer
    return ir.Select(ir.ICmp("eq", "ptr", p.Owner, "null"), "i64", "0", elements);
}

// StringSlice.ToString(): a new string with the bytes of the view (owned).
string StringSliceText(Compiler cg, Value v)
{
    var ir = cg.Ir;
    Value s = ToRValue(cg, v);
    HoldTemp(cg, s);
    var p = PartsOf(cg, s);
    string offset = ir.Cast("trunc", "i64", SliceOffset(cg, s.Type, p), "i32");
    string count = ir.Cast("trunc", "i64", p.Length, "i32");
    return ir.Call("ptr", "@__cs_substring", "ptr " + p.Owner + ", i32 " + offset + ", i32 " + count);
}

// Slice<T>.ToArray(): a new array with the elements of the view (references are counted).
Value SliceToArray(Compiler cg, Value v)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value s = ToRValue(cg, v);
    HoldTemp(cg, s);
    var p = PartsOf(cg, s);
    int arrayType = types.ArrayOf(types.Elem(s.Type));
    string copy = AllocArray(cg, types.Elem(s.Type), p.Length);
    ir.Call("void", ArrayHelper(cg, arrayType, "copy"), "ptr " + p.Owner + ", i64 " + SliceOffset(cg, s.Type, p) + ", ptr " + copy +
                                                        ", i64 0, i64 " + p.Length);
    return Rvalue(arrayType, copy, true);
}

// string/StringSlice == string/StringSlice: same length and same bytes.
Value EmitTextEquals(Compiler cg, BinOp op, Value l0, Value r0)
{
    var ir = cg.Ir;
    Value l = ToRValue(cg, l0);
    Value r = ToRValue(cg, r0);
    HoldTemp(cg, l);
    HoldTemp(cg, r);
    var a = PartsOf(cg, l);
    var b = PartsOf(cg, r);
    string sameLength = ir.ICmp("eq", "i64", a.Length, b.Length);
    string count = ir.Select(sameLength, "i64", a.Length, "0"); // compare nothing if the lengths differ
    string cmp = ir.Call("i32", "@memcmp", "ptr " + a.Data + ", ptr " + b.Data + ", i64 " + count);
    string eq = ir.Bin("and", "i1", sameLength, ir.ICmp("eq", "i32", cmp, "0"));
    return MakeBool(cg, op == BinOp.Eq ? eq : ir.Bin("xor", "i1", eq, "true"));
}

// __retain / __release of a slice: the reference to its owner block.
string SliceHelper(Compiler cg, int t, bool isRetain)
{
    var ir = cg.Ir;
    string name = "@\"" + (isRetain ? "__retain." : "__release.") + cg.Types.Name(t) + "\"";
    if (!ir.Declared.Add(name))
        return name;
    int owner = SliceOwnerType(cg, t);
    string fn = isRetain ? RetainFunction(cg, owner) : ReleaseFunction(cg, owner);
    ir.AppendHelper("define internal void " + name + "(" + LlvmType(cg, t) + " %v) {\nentry:\n" +
                    "  %owner = extractvalue " + LlvmType(cg, t) + " %v, 0\n  call void " + fn + "(ptr %owner)\n  ret void\n}\n\n");
    return name;
}
