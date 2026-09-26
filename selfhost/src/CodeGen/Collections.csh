// Collection expressions: [a, b, ..c]. The expression has no type of its own (type "collection", like a lambda); it
// is built when it is converted to the type it is used as:
//
//   T[]         a new array of exactly the right length
//   Slice<T>    the same array, as a view
//   a struct    with 'static X Create()' and 'Add(T)' (List<T>, HashSet<T>, your own): Create(), then Add per element
//
// Without a type to convert to (var x = [...], foreach, x.Length) it is an array of the first element's type. ..c
// spreads the elements of an array, a slice, or a struct with ToArray() (List<T>).

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// A struct that a collection expression can build: a static Create() without parameters and an Add with one.
bool IsCollectionBuilder(Compiler cg, int t)
{
    if (!cg.Types.IsStruct(t))
        return false;
    bool create = false;
    foreach (var c in MethodCandidates(cg, t, "Create"))
    {
        var d = cg.Funcs.Get(c.Entry).Decl;
        if (d.IsStatic && d.Params.Length == 0)
            create = true;
    }
    bool add = false;
    foreach (var c in MethodCandidates(cg, t, "Add"))
    {
        var d = cg.Funcs.Get(c.Entry).Decl;
        if (!d.IsStatic && d.Params.Length == 1)
            add = true;
    }
    return create && add;
}

int CollectionConversionCost(Compiler cg, int to)
{
    var types = cg.Types;
    if (types.IsArray(to) || types.Kind(to) == TypeKind.Slice || IsCollectionBuilder(cg, to))
        return 2;
    return -1;
}

// A collection expression used without a type to convert to becomes an array; other values stay as they are.
Value SettleCollection(Compiler cg, Value v)
{
    if (v.Type != cg.Types.Collection)
        return v;
    return EmitCollection(cg, v.CollectionNode, 0, v.CollectionNode.Loc);
}

// The source of ..c: an array or a slice (a struct with ToArray() is converted first).
Value SpreadSource(Compiler cg, Expr item)
{
    var types = cg.Types;
    Value src = ToRValue(cg, SettleCollection(cg, EmitRValue(cg, item)));
    if (types.IsStruct(src.Type) && MethodCandidates(cg, src.Type, "ToArray").Length > 0)
        src = EmitMethodCallOn(cg, src, "ToArray", new Arg[0], new int[0], item.Loc);
    if (!types.IsArray(src.Type) && types.Kind(src.Type) != TypeKind.Slice)
        Fail(cg, item.Loc, "'..' spreads an array, a slice or a collection with ToArray(), not '" + types.Name(src.Type) + "'");
    HoldTemp(cg, src);
    return src;
}

// [a, b, ..c] as the type 'to' (0: an array of the first element's type).
Value EmitCollection(Compiler cg, Expr e, int to, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetCollection(e);
    if (to != 0 && types.IsStruct(to))
        return EmitCollectionBuilder(cg, n, to, loc);
    if (to != 0 && !types.IsArray(to) && types.Kind(to) != TypeKind.Slice)
        Fail(cg, loc, "a collection expression cannot become '" + types.Name(to) + "' (only arrays, Slice<T> and structs with Create() and Add())");

    // the items, left to right: owned element values, and for ..c the part of c to copy
    int elem = to == 0 ? 0 : types.Elem(to);
    var values = new string[n.Items.Length];
    var owners = new string[n.Items.Length];
    var offsets = new string[n.Items.Length];
    var lengths = new string[n.Items.Length];
    for (var i = 0; i < n.Items.Length; i += 1)
    {
        Expr item = n.Items[i];
        if (n.Spread[i])
        {
            Value src = SpreadSource(cg, item);
            if (elem == 0)
                elem = types.Elem(src.Type);
            else if (types.Elem(src.Type) != elem)
                Fail(cg, item.Loc, "cannot spread '" + types.Name(src.Type) + "' into a collection of '" + types.Name(elem) + "'");
            var parts = PartsOf(cg, src);
            owners[i] = parts.Owner;
            lengths[i] = parts.Length;
            offsets[i] = types.IsArray(src.Type) ? "0" : SliceOffset(cg, src.Type, parts);
            continue;
        }
        Value v = SettleCollection(cg, EmitRValue(cg, item));
        if (elem == 0)
        {
            var k = types.Kind(v.Type);
            if (k == TypeKind.Null || k == TypeKind.ErrorLit || k == TypeKind.Lambda || k == TypeKind.MethodGroup || k == TypeKind.Void)
                Fail(cg, item.Loc, "cannot infer the element type from '" + types.Name(v.Type) + "'; give the collection a type (e.g. string[] a = [...];)");
            elem = v.Type;
        }
        values[i] = Consume(cg, ConvertValue(cg, v, elem, item.Loc));
    }
    if (elem == 0)
        Fail(cg, loc, "cannot infer the type of '[]' here; give it a type (e.g. int[] a = [];)");

    // one array of exactly the right length
    int arrayType = types.ArrayOf(elem);
    string elemIr = LlvmType(cg, elem);
    string total = "0";
    int plain = 0;
    for (var i = 0; i < n.Items.Length; i += 1)
    {
        if (n.Spread[i])
            total = ir.Bin("add", "i64", total, lengths[i]);
        else
            plain += 1;
    }
    total = ir.Bin("add", "i64", total, plain.ToString());
    string arr = AllocArray(cg, elem, total);
    string first = DataPtr(cg, arr);
    string at = "0";
    for (var i = 0; i < n.Items.Length; i += 1)
    {
        if (n.Spread[i])
        {
            ir.Call("void", ArrayHelper(cg, arrayType, "copy"), "ptr " + owners[i] + ", i64 " + offsets[i] + ", ptr " + arr +
                                                                ", i64 " + at + ", i64 " + lengths[i]);
            at = ir.Bin("add", "i64", at, lengths[i]);
        }
        else
        {
            ir.Store(elemIr, values[i], ir.Gep(elemIr, first, "i64 " + at)); // the new array takes over the reference
            at = ir.Bin("add", "i64", at, "1");
        }
    }
    if (to != 0 && types.Kind(to) == TypeKind.Slice)
    {
        // the view of the whole new array; it takes over the array's reference
        string ty = LlvmType(cg, to);
        string agg = ir.InsertValue(ty, "zeroinitializer", "ptr", arr, "0");
        agg = ir.InsertValue(ty, agg, "ptr", first, "1");
        agg = ir.InsertValue(ty, agg, "i64", total, "2");
        return Rvalue(to, agg, true);
    }
    return Rvalue(arrayType, arr, true);
}

// [a, b, ..c] as a struct with Create() and Add(T): Create(), then Add for every element.
Value EmitCollectionBuilder(Compiler cg, CollectionExpr n, int to, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    if (!IsCollectionBuilder(cg, to))
        Fail(cg, loc, "a collection expression cannot become '" + types.Name(to) + "': it needs 'static " + types.Name(to) +
                      " Create()' and 'Add(T)'");
    int create = ResolveOverload(cg, MethodCandidates(cg, to, "Create"), new Arg[0], new int[0], loc, "Create");
    Value made = EmitDirectCall(cg, create, "", new Arg[0], loc);
    string ty = LlvmType(cg, to);
    string slot = ir.Alloca(ty, "collection");
    ir.Store(ty, Consume(cg, ConvertValue(cg, made, to, loc)), slot);
    Value coll = Lvalue(to, slot, false);

    for (var i = 0; i < n.Items.Length; i += 1)
    {
        Expr item = n.Items[i];
        var args = new Arg[1];
        if (!n.Spread[i])
        {
            args[0] = Arg { V = SettleCollection(cg, EmitRValue(cg, item)), Source = item };
            EmitMethodCallOn(cg, coll, "Add", args, new int[0], item.Loc);
            continue;
        }
        // ..c: Add(c[k]) for every element
        Value src = SpreadSource(cg, item);
        var parts = PartsOf(cg, src);
        int srcElem = types.Elem(src.Type);
        string idxSlot = ir.Alloca("i64", "spread.idx");
        ir.Store("i64", "0", idxSlot);
        string condLabel = ir.NewLabel("spread.cond");
        string bodyLabel = ir.NewLabel("spread.body");
        string endLabel = ir.NewLabel("spread.end");
        ir.Br(condLabel);
        ir.SetBlock(condLabel);
        string idx = ir.Load("i64", idxSlot);
        ir.CondBr(ir.ICmp("ult", "i64", idx, parts.Length), bodyLabel, endLabel);
        ir.SetBlock(bodyLabel);
        int mark = cg.Fn[0].Temps.Count();
        args[0] = Arg { V = Lvalue(srcElem, ir.Gep(LlvmType(cg, srcElem), parts.Data, "i64 " + idx), true), Source = item };
        EmitMethodCallOn(cg, coll, "Add", args, new int[0], item.Loc);
        FlushTemps(cg, mark, true); // per element: the result of Add and its temporaries
        ir.Store("i64", ir.Bin("add", "i64", idx, "1"), idxSlot);
        ir.Br(condLabel);
        ir.SetBlock(endLabel);
    }
    // the value leaves the slot (it is not a variable, so nothing releases it there)
    return Rvalue(to, ir.Load(ty, slot), true);
}
