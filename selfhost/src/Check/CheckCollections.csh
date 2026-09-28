// Collection expressions [a, b, ..c] (see CodeGen/Collections.csh). Like in code generation the expression has no type
// of its own; its items are checked once where it stands, and the rest (the element type, spreads, the target type)
// where it is converted to the type it is used as, or settled to an array without one.

namespace CShift.Check;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;
using CShift.CodeGen;

// [a, b, ..c] where it stands: the values of its items (an inner [..] stays a collection value until the element type is
// known), kept for the conversion.
Value CheckCollectionExpr(Compiler cg, Expr e)
{
    var n = cg.Tree.GetCollection(e);
    var items = new Value[n.Items.Length];
    for (var i = 0; i < n.Items.Length; i += 1)
        items[i] = CheckRValue(cg, n.Items[i]);
    cg.CheckedCollections.Set(e.Index, items);
    Value v = Rvalue(cg.Types.Collection, "", false);
    v.CollectionNode = e;
    return v;
}

// A collection value used without a type to convert to is an array (see SettleCollection); other values stay.
Value SettleChecked(Compiler cg, Value v)
{
    if (v.Type != cg.Types.Collection)
        return v;
    return CheckCollectionAs(cg, v.CollectionNode, 0, v.CollectionNode.Loc);
}

// The conversion of a collection value to 'to' (see ConvertValue, EmitCollection, EmitFixedCollection and
// EmitCollectionBuilder); 0: an array of the first element's type.
Value CheckCollectionAs(Compiler cg, Expr e, int to, SourceLoc loc)
{
    var types = cg.Types;
    var n = cg.Tree.GetCollection(e);
    Value[] items = cg.CheckedCollections.Get(e.Index);
    if (to != 0 && types.IsResultLike(to))
    {
        // [..] as Optional<T> / Error<T>: the T
        if (IsUnknown(cg, CheckCollectionAs(cg, e, types.Elem(to), loc)))
            return UnknownValue(cg);
        return Rvalue(to, "", false);
    }
    if (to != 0 && types.IsStruct(to))
        return CheckCollectionBuilder(cg, n, items, to, loc);
    if (to != 0 && types.IsFixed(to))
    {
        int elem = types.Elem(to);
        bool hasSpread = false;
        foreach (var spread in n.Spread)
        {
            if (spread)
                hasSpread = true;
        }
        if (hasSpread)
            CheckCollectionAs(cg, e, types.ArrayOf(elem), loc);
        else if (n.Items.Length != types.Count(to))
            CheckError(cg, loc, "'" + types.Name(to) + "' needs " + types.Count(to).ToString() +
                                " elements, but the collection expression has " + n.Items.Length.ToString());
        else
        {
            for (var i = 0; i < n.Items.Length; i += 1)
                CheckConversion(cg, items[i], elem, n.Items[i].Loc);
        }
        return Rvalue(to, "", false);
    }
    if (to != 0 && !types.IsArray(to) && !types.IsElemSlice(to))
    {
        CheckError(cg, loc, "a collection expression cannot become '" + types.Name(to) +
                            "' (only arrays, Slice<T>, ReadOnlySlice<T>, Fixed<T, N> and structs with Create() and Add())");
        return UnknownValue(cg);
    }

    int elemType = to == 0 ? 0 : types.Elem(to);
    for (var i = 0; i < n.Items.Length; i += 1)
    {
        Expr item = n.Items[i];
        if (n.Spread[i])
        {
            Value src = CheckSpreadSource(cg, items[i], item);
            if (IsUnknown(cg, src))
            {
                if (elemType == 0)
                    return UnknownValue(cg);
                continue;
            }
            if (elemType == 0)
                elemType = types.Elem(src.Type);
            else if (types.Elem(src.Type) != elemType)
                CheckError(cg, item.Loc, "cannot spread '" + types.Name(src.Type) + "' into a collection of '" + types.Name(elemType) + "'");
            continue;
        }
        Value v = items[i];
        if (elemType == 0)
        {
            v = SettleChecked(cg, v);
            if (IsUnknown(cg, v))
                return UnknownValue(cg);
            var k = types.Kind(v.Type);
            if (k == TypeKind.Null || k == TypeKind.ErrorLit || k == TypeKind.Lambda || k == TypeKind.MethodGroup || k == TypeKind.Void)
            {
                CheckError(cg, item.Loc, "cannot infer the element type from '" + types.Name(v.Type) +
                                         "'; give the collection a type (e.g. string[] a = [...];)");
                return UnknownValue(cg);
            }
            elemType = v.Type;
        }
        CheckConversion(cg, v, elemType, item.Loc);
    }
    if (elemType == 0)
    {
        CheckError(cg, loc, "cannot infer the type of '[]' here; give it a type (e.g. int[] a = [];)");
        return UnknownValue(cg);
    }
    if (to != 0 && types.IsElemSlice(to))
        return Rvalue(to, "", false);
    return Rvalue(types.ArrayOf(elemType), "", false);
}

// The source of ..c: an array or a slice (a struct with ToArray() is converted first); unknown after an error.
Value CheckSpreadSource(Compiler cg, Value src, Expr item)
{
    var types = cg.Types;
    src = SettleChecked(cg, src);
    if (IsUnknown(cg, src))
        return src;
    if (types.IsStruct(src.Type) && MethodCandidates(cg, src.Type, "ToArray").Length > 0)
    {
        src = CheckMethodCallOn(cg, src, "ToArray", new Arg[0], true, new int[0], item.Loc);
        if (IsUnknown(cg, src))
            return src;
    }
    if (!types.IsArray(src.Type) && !types.IsElemSlice(src.Type))
    {
        CheckError(cg, item.Loc, "'..' spreads an array, a slice or a collection with ToArray(), not '" + types.Name(src.Type) + "'");
        return UnknownValue(cg);
    }
    return src;
}

// [a, b, ..c] as a struct with Create() and Add(T): Add is called for every element.
Value CheckCollectionBuilder(Compiler cg, CollectionExpr n, Value[] items, int to, SourceLoc loc)
{
    var types = cg.Types;
    if (!IsCollectionBuilder(cg, to))
    {
        CheckError(cg, loc, "a collection expression cannot become '" + types.Name(to) + "': it needs 'static " + types.Name(to) +
                            " Create()' and 'Add(T)'");
        return UnknownValue(cg);
    }
    string why = "";
    CheckOverload(cg, MethodCandidates(cg, to, "Create"), new Arg[0], new int[0], loc, "Create", ref why);
    if (ReportIf(cg, loc, why))
        return UnknownValue(cg);
    Value coll = Lvalue(to, "%c", false);
    for (var i = 0; i < n.Items.Length; i += 1)
    {
        Expr item = n.Items[i];
        var args = new Arg[1];
        if (!n.Spread[i])
        {
            Value v = SettleChecked(cg, items[i]);
            if (IsUnknown(cg, v))
                continue;
            args[0] = Arg { V = v, Source = item };
            CheckMethodCallOn(cg, coll, "Add", args, true, new int[0], item.Loc);
            continue;
        }
        Value src = CheckSpreadSource(cg, items[i], item);
        if (IsUnknown(cg, src))
            continue;
        args[0] = Arg { V = Lvalue(types.Elem(src.Type), "%e", true), Source = item };
        CheckMethodCallOn(cg, coll, "Add", args, true, new int[0], item.Loc);
    }
    return Rvalue(to, "", false);
}

// Overload resolution (TryResolveOverload), then the conversion of collection arguments to the chosen parameters (see
// EmitDirectCall).
int CheckOverload(Compiler cg, Candidate[] cands, Arg[] args, int[] typeArgs, SourceLoc loc, string name, ref string why)
{
    if (HasUnknownType(cg, typeArgs))
    {
        why = AlreadyReported(); // Foo<Bar>(...) with an unknown Bar
        return -1;
    }
    int instance = TryResolveOverload(cg, cands, args, typeArgs, loc, name, ref why);
    if (instance < 0 || why.Length > 0)
        return instance;
    var fi = cg.Instances.Get(instance);
    for (var i = 0; i < fi.ParamTypes.Length && i < args.Length; i += 1)
    {
        if (args[i].V.Type == cg.Types.Collection && fi.ParamRefs[i] == 0 && !IsInterfaceType(cg, fi.ParamTypes[i]))
            CheckCollectionAs(cg, args[i].V.CollectionNode, fi.ParamTypes[i], args[i].Source.IsNull() ? loc : args[i].Source.Loc);
    }
    return instance;
}
