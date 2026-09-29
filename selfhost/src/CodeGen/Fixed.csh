// Fixed<T, N>: N elements of T stored inline - in the variable (on the stack) or inside the struct that has the field.
// A Fixed is a value like a struct: assigning, passing and returning it copies the elements, so nothing can refer to
// it after it is gone. Heap arrays (T[]) and Fixed never convert into each other implicitly: ToArray() copies out,
// [..array] copies in. The LLVM type is [N x T].

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// The most elements a Fixed<T, N> may have (it lives on the stack or inside a struct).
const int MaxFixedCount = 1048576;

// Fixed<T, N> as written in the source: an element type and a number (or an integer constant).
int ResolveFixedType(Compiler cg, TypeRefNode node, int file, Dictionary<string, int> env)
{
    var types = cg.Types;
    if (node.Args.Length != 2)
        return RecoverType(cg, node.Loc, "'Fixed' expects an element type and a number of elements, e.g. Fixed<int, 16>");
    if (cg.Tree.GetType(node.Args[0]).Kind == TypeRefKind.Number)
        return RecoverType(cg, node.Loc, "the first type argument of 'Fixed' is the element type, e.g. Fixed<int, 16>");
    int elem = ResolveValueType(cg, node.Args[0].Id, file, env);
    if (types.IsVoid(elem))
        return RecoverType(cg, node.Loc, "a Fixed of 'void' is not allowed");
    int count = FixedCount(cg, node.Args[1], file);
    if (count == 0)
        return types.Unknown;
    return types.FixedOf(elem, count);
}

// An N of Fixed<T, N> that is not valid: Recover, and 0 (the Fixed type is unknown).
int RecoverCount(Compiler cg, SourceLoc loc, string message)
{
    Recover(cg, loc, message);
    return 0;
}

// The N of Fixed<T, N>: a number or the name of an integer constant, between 1 and MaxFixedCount.
int FixedCount(Compiler cg, TypeRef arg, int file)
{
    var types = cg.Types;
    var node = cg.Tree.GetType(arg);
    uint64 value = 0;
    bool negative = false;
    if (node.Kind == TypeRefKind.Number)
    {
        // the digits of the literal; anything above the limit is reported below
        string digits = node.Path[0];
        for (var i = 0; i < digits.Length && value <= (uint64)MaxFixedCount; i += 1)
            value = value * 10ul + (uint64)((int)digits[i] - 48);
    }
    else if (node.Kind == TypeRefKind.Named && node.Args.Length == 0)
    {
        string dotted = string.Join(".", node.Path);
        int c = LookupConst(cg, file, dotted);
        if (c < 0)
            return RecoverCount(cg, node.Loc, "the size of Fixed<T, N> must be a number or an integer constant, not '" + dotted + "'");
        ConstVal v = ConstEvalDecl(cg, c);
        if (v.Kind == ConstKind.Unknown)
            return 0; // Fixed<T, N> is unknown (ResolveFixedType)
        if (v.Kind != ConstKind.Int || !types.IsIntegral(v.Type) || types.IsEnum(v.Type))
            return RecoverCount(cg, node.Loc, "the size of Fixed<T, N> must be an integer constant, but '" + dotted + "' is '" + types.Name(v.Type) + "'");
        value = v.Mag;
        negative = v.Neg && v.Mag != 0;
    }
    else
    {
        return RecoverCount(cg, node.Loc, "the size of Fixed<T, N> must be a number or an integer constant");
    }
    if (negative || value < 1ul || value > (uint64)MaxFixedCount)
        return RecoverCount(cg, node.Loc, "the size of Fixed<T, N> must be between 1 and " + MaxFixedCount.ToString());
    return (int)value;
}

// The address of the elements of a Fixed value: its variable or field, or a copy in a new slot for a temporary.
string FixedAddress(Compiler cg, Value v)
{
    if (v.IsLValue)
        return v.V;
    HoldTemp(cg, v);
    string ty = LlvmType(cg, v.Type);
    string slot = cg.Ir.Alloca(ty, "fixed");
    cg.Ir.Store(ty, v.V, slot);
    return slot;
}

// f[i] and f[^i]: bounds-checked (a constant index when the program is compiled). An element of a variable or field is
// assignable unless the Fixed is read-only (a 'const ref' parameter).
Value EmitFixedElement(Compiler cg, Value obj, Expr index, bool fromEnd, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    int n = types.Count(obj.Type);
    int elem = types.Elem(obj.Type);
    if (index.Kind == ExprKind.IntLit)
    {
        uint64 raw = cg.Tree.GetIntLit(index).Value;
        bool bad = fromEnd ? (raw < 1ul || raw > (uint64)n) : raw >= (uint64)n;
        if (bad)
            Fail(cg, index.Loc, "index " + (fromEnd ? "^" : "") + raw.ToString() + " is out of range for '" + types.Name(obj.Type) + "' (" +
                                n.ToString() + " elements)");
    }
    string addr = FixedAddress(cg, obj);
    string i = SliceBound(cg, index, fromEnd, n.ToString());
    EmitIndexPanicIf(cg, ir.ICmp("uge", SizeIr(cg), i, n.ToString()), "fixed array index out of range", i, n.ToString());
    string p = ir.Gep(LlvmType(cg, elem), addr, SizeIr(cg) + " " + i);
    if (!obj.IsLValue)
        return Rvalue(elem, ir.Load(LlvmType(cg, elem), p), false);
    return Lvalue(elem, p, obj.IsConst);
}

// A counting loop over the N elements, emitted inline: BeginFixedLoop ... EndFixedLoop; Index is the position (a size).
struct FixedLoop
{
    string Slot;
    string Index;
    string Cond;
    string End;
}

FixedLoop BeginFixedLoop(Compiler cg, int n)
{
    var ir = cg.Ir;
    string slot = ir.Alloca(SizeIr(cg), "fixed.i");
    ir.Store(SizeIr(cg), "0", slot);
    string cond = ir.NewLabel("fixed.cond");
    string body = ir.NewLabel("fixed.body");
    string end = ir.NewLabel("fixed.end");
    ir.Br(cond);
    ir.SetBlock(cond);
    string i = ir.Load(SizeIr(cg), slot);
    ir.CondBr(ir.ICmp("ult", SizeIr(cg), i, n.ToString()), body, end);
    ir.SetBlock(body);
    return FixedLoop { Slot = slot, Index = i, Cond = cond, End = end };
}

void EndFixedLoop(Compiler cg, FixedLoop loop)
{
    var ir = cg.Ir;
    ir.Store(SizeIr(cg), ir.Bin("add", SizeIr(cg), loop.Index, "1"), loop.Slot);
    ir.Br(loop.Cond);
    ir.SetBlock(loop.End);
}

// f.ToArray(): a new heap array with copies of the elements.
Value FixedToArray(Compiler cg, Value obj)
{
    var types = cg.Types;
    var ir = cg.Ir;
    int elem = types.Elem(obj.Type);
    int n = types.Count(obj.Type);
    string et = LlvmType(cg, elem);
    string addr = FixedAddress(cg, obj);
    string arr = AllocArray(cg, elem, n.ToString());
    string data = DataPtr(cg, arr);
    var loop = BeginFixedLoop(cg, n);
    string x = ir.Load(et, ir.Gep(et, addr, SizeIr(cg) + " " + loop.Index));
    EmitRetain(cg, elem, x);
    ir.Store(et, x, ir.Gep(et, data, SizeIr(cg) + " " + loop.Index));
    EndFixedLoop(cg, loop);
    return Rvalue(types.ArrayOf(elem), arr, true);
}

// [a, b, ..c] as a Fixed<T, N>: without spreads the number of elements is checked now; with spreads the elements are
// collected in an array first and its length is checked when the program runs.
Value EmitFixedCollection(Compiler cg, Expr e, CollectionExpr n, int to, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    int count = types.Count(to);
    int elem = types.Elem(to);
    string ty = LlvmType(cg, to);
    string et = LlvmType(cg, elem);
    bool hasSpread = false;
    foreach (var spread in n.Spread)
    {
        if (spread)
            hasSpread = true;
    }
    if (!hasSpread)
    {
        if (n.Items.Length != count)
            Fail(cg, loc, "'" + types.Name(to) + "' needs " + count.ToString() + " elements, but the collection expression has " +
                          n.Items.Length.ToString());
        string agg = "zeroinitializer";
        for (var i = 0; i < n.Items.Length; i += 1)
        {
            // the element type is known, so an inner [..] takes it (a Fixed of Fixed, an array, ...)
            string x = Consume(cg, ConvertValue(cg, EmitRValue(cg, n.Items[i]), elem, n.Items[i].Loc));
            agg = ir.InsertValue(ty, agg, et, x, i.ToString());
        }
        return Rvalue(to, agg, true);
    }
    Value arr = EmitCollection(cg, e, types.ArrayOf(elem), loc);
    HoldTemp(cg, arr);
    string length = ArrayLength(cg, arr.V);
    EmitPanicIf(cg, ir.ICmp("ne", SizeIr(cg), length, count.ToString()), "the collection for '" + types.Name(to) + "' does not have " +
                                                                        count.ToString() + " elements");
    string slot = ir.Alloca(ty, "fixed.init");
    string data = DataPtr(cg, arr.V);
    var loop = BeginFixedLoop(cg, count);
    string x = ir.Load(et, ir.Gep(et, data, SizeIr(cg) + " " + loop.Index));
    EmitRetain(cg, elem, x);
    ir.Store(et, x, ir.Gep(et, slot, SizeIr(cg) + " " + loop.Index));
    EndFixedLoop(cg, loop);
    return Rvalue(to, ir.Load(ty, slot), true);
}

// __retain / __release of a Fixed whose elements are counted: every element.
string FixedHelper(Compiler cg, int t, bool isRetain)
{
    var ir = cg.Ir;
    var types = cg.Types;
    string name = "@\"" + (isRetain ? "__retain." : "__release.") + types.Name(t) + "\"";
    if (!ir.Declared.Add(name))
        return name;
    int elem = types.Elem(t);
    string ty = LlvmType(cg, t);
    string et = LlvmType(cg, elem);
    string fn = isRetain ? RetainFunction(cg, elem) : ReleaseFunction(cg, elem);
    string n = types.Count(t).ToString();
    ir.AppendHelper(SizedText(cg, "define internal void " + name + "(" + ty + " %v) {\nentry:\n" +
                    "  %p = alloca " + ty + "\n  store " + ty + " %v, ptr %p\n  br label %loop\nloop:\n" +
                    "  %i = phi $S [ 0, %entry ], [ %next, %body ]\n  %done = icmp eq $S %i, " + n + "\n" +
                    "  br i1 %done, label %exit, label %body\nbody:\n" +
                    "  %e = getelementptr " + et + ", ptr %p, $S %i\n  %x = load " + et + ", ptr %e\n" +
                    "  call void " + fn + "(" + et + " %x)\n  %next = add $S %i, 1\n  br label %loop\nexit:\n  ret void\n}\n\n"));
    return name;
}
