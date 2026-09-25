// Arrays and strings as sequences: creation, indexing, foreach, Array.Copy, Clone and the per-type release of arrays
// (the array parts of CodeGenExpr.cpp, CodeGenStmt.cpp and CodeGenRuntime.cpp).
//
// An array is a heap block { i64 refcount, i64 length, elements... } like a string; a null array has length 0.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// The size of a type in bytes as a constant operand (the "getelementptr null" trick).
string SizeOfType(Compiler cg, int t)
{
    return "ptrtoint (ptr getelementptr (" + LlvmType(cg, t) + ", ptr null, i32 1) to i64)";
}

// The address of the first element of a block.
string DataPtr(Compiler cg, string block)
{
    return cg.Ir.ByteGep(block, "16");
}

string ArrayLength(Compiler cg, string block)
{
    return cg.Ir.Call("i64", "@__cs_len", "ptr " + block);
}

// The block of 'count' elements of the type, zeroed, with reference count 1.
string AllocArray(Compiler cg, int elem, string count)
{
    string bytes = cg.Ir.Bin("mul", "i64", count, SizeOfType(cg, elem));
    return cg.Ir.Call("ptr", "@__cs_alloc", "i64 " + bytes + ", i64 " + count);
}

// ---------------------------------------------------------------------------
// new T[n], new T[] { ... }
// ---------------------------------------------------------------------------

Value EmitNewArray(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetNewArray(e);
    int elem = DeclTypeOf(cg, n.ElemType);
    if (types.IsVoid(elem))
        Fail(cg, e.Loc, "cannot create an array of 'void'");
    int arrayType = types.ArrayOf(elem);
    string elemIr = LlvmType(cg, elem);

    if (n.HasInit)
    {
        if (!n.Size.IsNull())
        {
            if (n.Size.Kind != ExprKind.IntLit || (int64)cg.Tree.GetIntLit(n.Size).Value != n.Init.Length)
                Fail(cg, e.Loc, "the array size must match the number of initializers");
        }
        string arr = AllocArray(cg, elem, n.Init.Length.ToString());
        for (var i = 0; i < n.Init.Length; i += 1)
        {
            Value v = ConvertValue(cg, EmitRValue(cg, n.Init[i]), elem, n.Init[i].Loc);
            string owned = Consume(cg, v);
            string slot = ir.Gep(elemIr, DataPtr(cg, arr), "i64 " + i.ToString());
            ir.Store(elemIr, owned, slot);
        }
        return Rvalue(arrayType, arr, true);
    }

    Value size = EmitRValue(cg, n.Size);
    if (!types.IsIntegral(size.Type))
        Fail(cg, n.Size.Loc, "the array size must be an integer");
    bool isSigned = types.IsInt(size.Type) && types.IsSigned(size.Type);
    string count = NumericConvert(cg, size.V, size.Type, isSigned ? types.I64 : types.U64);
    if (isSigned)
        EmitPanicIf(cg, ir.ICmp("slt", "i64", count, "0"), "negative array length");
    return Rvalue(arrayType, AllocArray(cg, elem, count), true);
}

// ---------------------------------------------------------------------------
// a[i]
// ---------------------------------------------------------------------------

Value EmitIndex(Compiler cg, Expr e)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetIndex(e);
    Value obj = EmitExpr(cg, n.Object);
    Value idx = EmitRValue(cg, n.Index);
    if (!types.IsIntegral(idx.Type))
        Fail(cg, n.Index.Loc, "an index must be an integer, not '" + types.Name(idx.Type) + "'");
    bool signedIndex = types.IsInt(idx.Type) && types.IsSigned(idx.Type);
    string i64v = NumericConvert(cg, idx.V, idx.Type, signedIndex ? types.I64 : types.U64);

    int t = obj.Type;
    if (types.IsArray(t) || types.IsString(t))
    {
        Value arr = ToRValue(cg, obj);
        HoldTemp(cg, arr);
        string len = ArrayLength(cg, arr.V);
        EmitPanicIf(cg, ir.ICmp("uge", "i64", i64v, len), types.IsArray(t) ? "array index out of range" : "string index out of range");
        string data = DataPtr(cg, arr.V);
        if (types.IsString(t))
            return Rvalue(types.Char, ir.Load("i8", ir.Gep("i8", data, "i64 " + i64v)), false);
        return Lvalue(types.Elem(t), ir.Gep(LlvmType(cg, types.Elem(t)), data, "i64 " + i64v), false);
    }
    if (types.IsPointer(t))
    {
        RequireUnsafe(cg, e.Loc, "pointer indexing");
        if (types.IsVoid(types.Elem(t)))
            Fail(cg, e.Loc, "cannot index 'void*'");
        Value p = ToRValue(cg, obj);
        return Lvalue(types.Elem(t), ir.Gep(LlvmType(cg, types.Elem(t)), p.V, "i64 " + i64v), false);
    }
    Fail(cg, e.Loc, "cannot index a value of type '" + types.Name(t) + "'");
    return obj;
}

// ---------------------------------------------------------------------------
// foreach over an array or a string
// ---------------------------------------------------------------------------

void EmitForeach(Compiler cg, Stmt s)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetForeach(s);
    Value it = EmitRValue(cg, n.Iterable);
    int collType = it.Type;
    if (types.IsStruct(collType))
    {
        EmitForeachStruct(cg, s, it);
        return;
    }
    if (!types.IsArray(collType) && !types.IsString(collType))
        Fail(cg, n.Iterable.Loc, "'foreach' requires an array, a string or a struct with Count() and Get(int), not '" + types.Name(collType) + "'");
    int elemType = types.IsArray(collType) ? types.Elem(collType) : types.Char;

    PushScope(cg); // holds the collection so that it stays alive during the loop
    string collSlot = ir.Alloca("ptr", "foreach.coll");
    ir.Store("ptr", Consume(cg, it), collSlot);
    DeclareVar(cg, "$foreach", collType, collSlot);
    FlushTemps(cg, 0, true);

    string idxSlot = ir.Alloca("i64", "foreach.idx");
    ir.Store("i64", "0", idxSlot);
    string len = ArrayLength(cg, ir.Load("ptr", collSlot));

    string condLabel = ir.NewLabel("foreach.cond");
    string bodyLabel = ir.NewLabel("foreach.body");
    string incLabel = ir.NewLabel("foreach.inc");
    string endLabel = ir.NewLabel("foreach.end");
    ir.Br(condLabel);

    ir.SetBlock(condLabel);
    string idx = ir.Load("i64", idxSlot);
    ir.CondBr(ir.ICmp("ult", "i64", idx, len), bodyLabel, endLabel);

    ir.SetBlock(bodyLabel);
    int outerDepth = ScopeCount(cg);
    PushScope(cg); // per-iteration scope for the loop variable
    int varType = n.Type.IsNull() ? elemType : DeclTypeOf(cg, n.Type);
    string coll = ir.Load("ptr", collSlot);
    string addr = ir.Gep(LlvmType(cg, elemType), DataPtr(cg, coll), "i64 " + idx);
    Value elem = Lvalue(elemType, addr, true);
    Value cv = ConvertValue(cg, elem, varType, s.Loc);
    string varSlot = ir.Alloca(LlvmType(cg, varType), n.Name);
    ir.Store(LlvmType(cg, varType), Consume(cg, cv), varSlot);
    DeclareVar(cg, n.Name, varType, varSlot);

    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = endLabel, ContinueLabel = incLabel, ScopeDepth = outerDepth });
    EmitStmt(cg, n.Body);
    cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);
    PopScope(cg, true);
    ir.Br(incLabel);

    ir.SetBlock(incLabel);
    string next = ir.Bin("add", "i64", ir.Load("i64", idxSlot), "1");
    ir.Store("i64", next, idxSlot);
    ir.Br(condLabel);

    ir.SetBlock(endLabel);
    PopScope(cg, true);
}

// ---------------------------------------------------------------------------
// Array.Copy and Clone
// ---------------------------------------------------------------------------

// Array.Copy(source, sourceIndex, destination, destinationIndex, count) or Array.Copy(source, destination, count).
Value EmitArrayCopy(Compiler cg, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    if (args.Length != 5 && args.Length != 3)
        Fail(cg, loc, "Array.Copy takes (source, sourceIndex, destination, destinationIndex, count) or (source, destination, count)");
    bool shortForm = args.Length == 3;
    Value src = ToRValue(cg, args[0].V);
    Value dst = ToRValue(cg, args[shortForm ? 1 : 2].V);
    if (!types.IsArray(src.Type) || src.Type != dst.Type)
        Fail(cg, loc, "Array.Copy needs two arrays of the same type, got '" + types.Name(src.Type) + "' and '" + types.Name(dst.Type) + "'");
    HoldTemp(cg, src);
    HoldTemp(cg, dst);
    string si = "0";
    string di = "0";
    if (!shortForm)
    {
        si = ir.Cast("sext", "i32", ConvertValue(cg, args[1].V, types.I32, loc).V, "i64");
        di = ir.Cast("sext", "i32", ConvertValue(cg, args[3].V, types.I32, loc).V, "i64");
    }
    string count = ir.Cast("sext", "i32", ConvertValue(cg, args[shortForm ? 2 : 4].V, types.I32, loc).V, "i64");
    ir.Call("void", ArrayHelper(cg, src.Type, "copy"), "ptr " + src.V + ", i64 " + si + ", ptr " + dst.V + ", i64 " + di + ", i64 " + count);
    return Rvalue(types.Void, "", false);
}

Value EmitArrayClone(Compiler cg, Value obj)
{
    Value a = ToRValue(cg, obj);
    HoldTemp(cg, a);
    return Rvalue(a.Type, cg.Ir.Call("ptr", ArrayHelper(cg, a.Type, "clone"), "ptr " + a.V), true);
}

// ---------------------------------------------------------------------------
// Helper functions per array type
// ---------------------------------------------------------------------------

// The release function of a value type: strings and arrays without references inside are released flat.
string ReleaseFunction(Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsString(t))
        return "@__cs_release_flat";
    if (types.IsArray(t))
        return NeedsArc(cg, types.Elem(t)) ? ArrayHelper(cg, t, "release") : "@__cs_release_flat";
    if (types.IsStruct(t))
        return StructHelper(cg, t, false);
    if (types.IsResultLike(t) || types.Kind(t) == TypeKind.ErrorLit)
        return ResultHelper(cg, t, false);
    if (types.IsSharedPtr(t))
        return SharedReleaseHelper(cg, t);
    Fail(cg, SourceLoc { }, "cshc does not release values of type '" + types.Name(t) + "' yet");
    return "";
}

string RetainFunction(Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsString(t) || types.IsArray(t))
        return "@__cs_retain";
    if (types.IsStruct(t))
        return StructHelper(cg, t, true);
    if (types.IsResultLike(t) || types.Kind(t) == TypeKind.ErrorLit)
        return ResultHelper(cg, t, true);
    if (types.IsSharedPtr(t))
        return SharedRetainHelper(cg);
    Fail(cg, SourceLoc { }, "cshc does not count references of '" + types.Name(t) + "' yet");
    return "";
}

// SharedPtr<T>: an atomically reference-counted box {i64 count, i64 unused, T value}, safe to share between OS threads.
// Retaining is the same for every T, so one helper serves all of them.
string SharedRetainHelper(Compiler cg)
{
    string name = "@__cs_retain_shared";
    if (!cg.Ir.Declared.Add(name))
        return name;
    cg.Ir.AppendHelper("define internal void " + name + "(ptr %p) {\nentry:\n" +
                       "  %isnull = icmp eq ptr %p, null\n  br i1 %isnull, label %done, label %inc\n" +
                       "inc:\n  %old = atomicrmw add ptr %p, i64 1 monotonic\n  br label %done\n" +
                       "done:\n  ret void\n}\n\n");
    return name;
}

// Atomic decrement; the last owner releases the value (if it needs ARC) and frees the block. acq_rel so that the freeing
// thread sees every write the other owners made to the value before they let go of it.
string SharedReleaseHelper(Compiler cg, int t)
{
    string name = "@\"__release." + cg.Types.Name(t) + "\"";
    if (!cg.Ir.Declared.Add(name))
        return name;
    int elem = cg.Types.Elem(t);
    string releaseValue = "";
    if (NeedsArc(cg, elem))
    {
        string ty = LlvmType(cg, elem);
        releaseValue = "  %vp = getelementptr i8, ptr %p, i64 16\n  %v = load " + ty + ", ptr %vp\n" +
                       "  call void " + ReleaseFunction(cg, elem) + "(" + ty + " %v)\n";
    }
    string counter = cg.St[0].ArcStats
        ? "  %f = atomicrmw add ptr @__cs_frees, i64 1 monotonic\n"
        : "";
    cg.Ir.AppendHelper("define internal void " + name + "(ptr %p) {\nentry:\n" +
                       "  %isnull = icmp eq ptr %p, null\n  br i1 %isnull, label %done, label %dec\n" +
                       "dec:\n  %old = atomicrmw sub ptr %p, i64 1 acq_rel\n" +
                       "  %last = icmp eq i64 %old, 1\n  br i1 %last, label %free, label %done\n" +
                       "free:\n" + releaseValue + "  call void @free(ptr %p)\n" + counter + "  br label %done\n" +
                       "done:\n  ret void\n}\n\n");
    return name;
}

// "@"__release.T[]"", "@"__clone.T[]"", "@"__copy.T[]"": written the first time they are needed.
string ArrayHelper(Compiler cg, int arrayType, string kind)
{
    var ir = cg.Ir;
    string name = "@\"__" + kind + "." + cg.Types.Name(arrayType) + "\"";
    if (!ir.Declared.Add(name))
        return name;
    int elem = cg.Types.Elem(arrayType);
    string text = "";
    if (kind == "release")
        text = ArrayReleaseText(cg, name, elem);
    else if (kind == "clone")
        text = ArrayCloneText(cg, name, elem);
    else
        text = ArrayCopyText(cg, name, elem);
    ir.AppendHelper(text);
    return name;
}

string ArrayReleaseText(Compiler cg, string name, int elem)
{
    string ty = LlvmType(cg, elem);
    string counter = cg.St[0].ArcStats
        ? "  %f = atomicrmw add ptr @__cs_frees, i64 1 monotonic\n"
        : "";
    return "define internal void " + name + "(ptr %p) {\nentry:\n" +
           "  %isnull = icmp eq ptr %p, null\n  br i1 %isnull, label %done, label %dec\n" +
           "dec:\n  %rc0 = load i64, ptr %p\n  %rc = sub i64 %rc0, 1\n  store i64 %rc, ptr %p\n" +
           "  %lenp = getelementptr i8, ptr %p, i64 8\n  %len = load i64, ptr %lenp\n" +
           "  %zero = icmp eq i64 %rc, 0\n  br i1 %zero, label %loop, label %done\n" +
           "loop:\n  %i = phi i64 [ 0, %dec ], [ %next, %body ]\n" +
           "  %more = icmp ult i64 %i, %len\n  br i1 %more, label %body, label %free\n" +
           "body:\n  %data = getelementptr i8, ptr %p, i64 16\n" +
           "  %ep = getelementptr " + ty + ", ptr %data, i64 %i\n  %ev = load " + ty + ", ptr %ep\n" +
           "  call void " + ReleaseFunction(cg, elem) + "(" + ty + " %ev)\n" +
           "  %next = add i64 %i, 1\n  br label %loop\n" +
           "free:\n  call void @free(ptr %p)\n" + counter + "  br label %done\n" +
           "done:\n  ret void\n}\n\n";
}

string ArrayCloneText(Compiler cg, string name, int elem)
{
    string ty = LlvmType(cg, elem);
    string text = "define internal ptr " + name + "(ptr %p) {\nentry:\n" +
                  "  %isnull = icmp eq ptr %p, null\n  br i1 %isnull, label %null, label %copy\n" +
                  "null:\n  ret ptr null\n" +
                  "copy:\n  %lenp = getelementptr i8, ptr %p, i64 8\n  %len = load i64, ptr %lenp\n" +
                  "  %bytes = mul i64 %len, " + SizeOfType(cg, elem) + "\n" +
                  "  %r = call ptr @__cs_alloc(i64 %bytes, i64 %len)\n" +
                  "  %dst = getelementptr i8, ptr %r, i64 16\n  %src = getelementptr i8, ptr %p, i64 16\n" +
                  "  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %src, i64 %bytes, i1 false)\n";
    if (NeedsArc(cg, elem))
    {
        text += "  br label %loop\n" +
                "loop:\n  %i = phi i64 [ 0, %copy ], [ %next, %body ]\n" +
                "  %more = icmp ult i64 %i, %len\n  br i1 %more, label %body, label %done\n" +
                "body:\n  %ep = getelementptr " + ty + ", ptr %dst, i64 %i\n  %ev = load " + ty + ", ptr %ep\n" +
                "  call void " + RetainFunction(cg, elem) + "(" + ty + " %ev)\n" +
                "  %next = add i64 %i, 1\n  br label %loop\n" +
                "done:\n  ret ptr %r\n}\n\n";
        return text;
    }
    return text + "  ret ptr %r\n}\n\n";
}

// copy(src, srcIndex, dst, dstIndex, count): bounds-checked, also for overlapping ranges of one array. Arrays with
// references inside copy element by element (retain the new value, release the old one).
string ArrayCopyText(Compiler cg, string name, int elem)
{
    string ty = LlvmType(cg, elem);
    string text = "define internal void " + name + "(ptr %src, i64 %si, ptr %dst, i64 %di, i64 %count) {\nentry:\n" +
                  "  %srclen = call i64 @__cs_len(ptr %src)\n  %dstlen = call i64 @__cs_len(ptr %dst)\n" +
                  "  %b1 = icmp slt i64 %si, 0\n  %b2 = icmp slt i64 %di, 0\n  %b3 = icmp slt i64 %count, 0\n" +
                  "  %e1 = add i64 %si, %count\n  %b4 = icmp sgt i64 %e1, %srclen\n" +
                  "  %e2 = add i64 %di, %count\n  %b5 = icmp sgt i64 %e2, %dstlen\n" +
                  "  %o1 = or i1 %b1, %b2\n  %o2 = or i1 %o1, %b3\n  %o3 = or i1 %o2, %b4\n  %bad = or i1 %o3, %b5\n" +
                  "  br i1 %bad, label %range, label %ok\n" +
                  "range:\n  call void @__cs_panic(ptr " + cg.Ir.CString("array copy out of range") + ")\n  unreachable\n" +
                  "ok:\n  %sdata = getelementptr i8, ptr %src, i64 16\n  %ddata = getelementptr i8, ptr %dst, i64 16\n" +
                  "  %sbase = getelementptr " + ty + ", ptr %sdata, i64 %si\n" +
                  "  %dbase = getelementptr " + ty + ", ptr %ddata, i64 %di\n";
    if (!NeedsArc(cg, elem))
    {
        return text + "  %bytes = mul i64 %count, " + SizeOfType(cg, elem) + "\n" +
               "  call void @llvm.memmove.p0.p0.i64(ptr %dbase, ptr %sbase, i64 %bytes, i1 false)\n  ret void\n}\n\n";
    }
    text += "  %same = icmp eq ptr %src, %dst\n  %ahead = icmp sgt i64 %di, %si\n" +
            "  %backward = and i1 %same, %ahead\n  br i1 %backward, label %bwd.head, label %fwd.head\n";
    text += CopyLoop(cg, ty, elem, "fwd", false) + CopyLoop(cg, ty, elem, "bwd", true);
    return text + "done:\n  ret void\n}\n\n";
}

// One direction of the element-wise copy loop.
string CopyLoop(Compiler cg, string ty, int elem, string prefix, bool backward)
{
    string index = backward ? "%" + prefix + ".rev" : "%" + prefix + ".i";
    string text = prefix + ".head:\n  %" + prefix + ".i = phi i64 [ 0, %ok ], [ %" + prefix + ".next, %" + prefix + ".body ]\n" +
                  "  %" + prefix + ".more = icmp slt i64 %" + prefix + ".i, %count\n" +
                  "  br i1 %" + prefix + ".more, label %" + prefix + ".body, label %done\n" +
                  prefix + ".body:\n";
    if (backward)
        text += "  %bwd.last = sub i64 %count, 1\n  %bwd.rev = sub i64 %bwd.last, %bwd.i\n";
    text += "  %" + prefix + ".sp = getelementptr " + ty + ", ptr %sbase, i64 " + index + "\n" +
            "  %" + prefix + ".dp = getelementptr " + ty + ", ptr %dbase, i64 " + index + "\n" +
            "  %" + prefix + ".v = load " + ty + ", ptr %" + prefix + ".sp\n" +
            "  call void " + RetainFunction(cg, elem) + "(" + ty + " %" + prefix + ".v)\n" +
            "  %" + prefix + ".old = load " + ty + ", ptr %" + prefix + ".dp\n" +
            "  store " + ty + " %" + prefix + ".v, ptr %" + prefix + ".dp\n" +
            "  call void " + ReleaseFunction(cg, elem) + "(" + ty + " %" + prefix + ".old)\n" +
            "  %" + prefix + ".next = add i64 %" + prefix + ".i, 1\n  br label %" + prefix + ".head\n";
    return text;
}

// ---------------------------------------------------------------------------
// foreach over a struct: it must provide "int Count()" and "T Get(int index)" (e.g. List<T>)
// ---------------------------------------------------------------------------

int FindForeachMethod(Compiler cg, int collType, string name, Arg[] probe, SourceLoc loc)
{
    var cands = MethodCandidates(cg, collType, name);
    if (cands.Length == 0)
        Fail(cg, loc, "'foreach' over struct '" + cg.Types.Name(collType) + "' needs the methods 'int Count()' and 'T Get(int index)'");
    return ResolveOverload(cg, cands, probe, new int[0], loc, name);
}

void EmitForeachStruct(Compiler cg, Stmt s, Value it)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var n = cg.Tree.GetForeach(s);
    int collType = it.Type;
    SourceLoc loc = n.Iterable.Loc;
    int countInstance = FindForeachMethod(cg, collType, "Count", new Arg[0], loc);
    var probe = new Arg[1];
    probe[0] = Arg { V = ConstInt(cg, types.I32, 0) };
    int getInstance = FindForeachMethod(cg, collType, "Get", probe, loc);
    var countFn = cg.Instances.Get(countInstance);
    var getFn = cg.Instances.Get(getInstance);
    if (!countFn.HasThis || !getFn.HasThis || countFn.Ret != types.I32 || types.IsVoid(getFn.Ret) ||
        getFn.ParamTypes[0] != types.I32 || getFn.ParamRefs[0] != 0)
        Fail(cg, loc, "'foreach' over struct '" + types.Name(collType) + "' needs the methods 'int Count()' and 'T Get(int index)'");
    UseFunction(cg, countInstance);
    UseFunction(cg, getInstance);
    NoteCall(cg, countInstance);
    NoteCall(cg, getInstance);

    PushScope(cg); // holds a copy of the struct for the duration of the loop
    string collIr = LlvmType(cg, collType);
    string collSlot = ir.Alloca(collIr, "foreach.coll");
    ir.Store(collIr, Consume(cg, it), collSlot);
    DeclareVar(cg, "$foreach", collType, collSlot);
    FlushTemps(cg, 0, true);

    string idxSlot = ir.Alloca("i32", "foreach.idx");
    ir.Store("i32", "0", idxSlot);

    string condLabel = ir.NewLabel("foreach.cond");
    string bodyLabel = ir.NewLabel("foreach.body");
    string incLabel = ir.NewLabel("foreach.inc");
    string endLabel = ir.NewLabel("foreach.end");
    ir.Br(condLabel);

    ir.SetBlock(condLabel);
    string idx = ir.Load("i32", idxSlot);
    string count = ir.Call("i32", countFn.LlvmName, "ptr " + collSlot);
    ir.CondBr(ir.ICmp("slt", "i32", idx, count), bodyLabel, endLabel);

    ir.SetBlock(bodyLabel);
    int outerDepth = ScopeCount(cg);
    PushScope(cg);
    int elemType = getFn.Ret;
    int varType = n.Type.IsNull() ? elemType : DeclTypeOf(cg, n.Type);
    string got = ir.Call(LlvmType(cg, elemType), getFn.LlvmName, "ptr " + collSlot + ", i32 " + idx);
    Value elem = Rvalue(elemType, got, NeedsArc(cg, elemType));
    Value cv = ConvertValue(cg, elem, varType, loc);
    string varSlot = ir.Alloca(LlvmType(cg, varType), n.Name);
    ir.Store(LlvmType(cg, varType), Consume(cg, cv), varSlot);
    DeclareVar(cg, n.Name, varType, varSlot);

    cg.Fn[0].Loops.Add(LoopCtx { BreakLabel = endLabel, ContinueLabel = incLabel, ScopeDepth = outerDepth });
    EmitStmt(cg, n.Body);
    cg.Fn[0].Loops.RemoveAt(cg.Fn[0].Loops.Count() - 1);
    PopScope(cg, true);
    ir.Br(incLabel);

    ir.SetBlock(incLabel);
    string next = ir.Bin("add", "i32", ir.Load("i32", idxSlot), "1");
    ir.Store("i32", next, idxSlot);
    ir.Br(condLabel);

    ir.SetBlock(endLabel);
    PopScope(cg, true);
}

// string.FromBytes(uint8[] bytes [, start, count]): a string from raw (UTF-8) bytes.
Value EmitStringFromBytes(Compiler cg, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    if (args.Length == 0 || args.Length == 2 || args.Length > 3)
        Fail(cg, loc, "string.FromBytes takes (bytes) or (bytes, start, count)");
    Value bytes = ToRValue(cg, args[0].V);
    int byteArray = types.ArrayOf(types.U8);
    if (bytes.Type != byteArray && types.Kind(bytes.Type) != TypeKind.Null)
        Fail(cg, loc, "string.FromBytes needs a 'uint8[]', not '" + types.Name(bytes.Type) + "'");
    HoldTemp(cg, bytes);
    string start = "0";
    string count = ir.Cast("trunc", "i64", ArrayLength(cg, bytes.V), "i32");
    if (args.Length == 3)
    {
        start = ConvertValue(cg, args[1].V, types.I32, loc).V;
        count = ConvertValue(cg, args[2].V, types.I32, loc).V;
    }
    // Arrays and strings share the block layout, so the substring helper copies the bytes.
    return Rvalue(types.String, ir.Call("ptr", "@__cs_substring", "ptr " + bytes.V + ", i32 " + start + ", i32 " + count), true);
}
