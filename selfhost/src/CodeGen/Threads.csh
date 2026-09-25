// Real OS threads: 'thread' functions, 'start f(...)' and Thread / Thread<T> (port of CodeGenThread.cpp).
//
//     thread int Square(int x) { return x * x; }
//
//     Thread<int> t = start Square(6);
//     Console.WriteLine(t.Join());   // 36
//
// The mutex/condition-variable protocol, Join/Cancel and the 'is' pattern are CShift code in stdlib/thread.csh. This file
// does what cannot be written in CShift: the checks of a thread function's signature and of its purity (it never touches
// a global, not even through the functions it calls), the call site of a spawn (control block, argument block,
// pthread_create), the trampoline pthread_create calls, and 'Thread.Cancelled'.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// ---------------------------------------------------------------------------
// Signature checks
// ---------------------------------------------------------------------------

// Plain values (no reference counting at all) and SharedPtr<T> (atomic count). Strings, arrays, containers, Error<T>,
// pointers and Action/Func are not allowed: copying them into another thread would race on a non-atomic count or alias
// data the other thread does not expect.
bool IsThreadSafeType(Compiler cg, int t)
{
    var types = cg.Types;
    var kind = types.Kind(t);
    if (kind == TypeKind.Bool || kind == TypeKind.Int || kind == TypeKind.Char || kind == TypeKind.Float || kind == TypeKind.Enum ||
        kind == TypeKind.SharedPtr)
        return true;
    if (kind == TypeKind.Optional)
        return IsThreadSafeType(cg, types.Elem(t));
    if (kind != TypeKind.Struct)
        return false;
    var si = GetStructInfo(cg, t);
    if (si.LayoutInProgress)
        return false;
    if (si.Base != 0 && !IsThreadSafeType(cg, si.Base))
        return false;
    foreach (var f in si.Fields)
    {
        if (!IsThreadSafeType(cg, f.Type))
            return false;
    }
    return true;
}

// Called by EnsureSignature once the parameter types of a 'thread' function are known.
void CheckThreadSignature(Compiler cg, FuncInfo fi)
{
    var d = cg.Funcs.Get(fi.Entry).Decl;
    if (d.TypeParams.Length > 0)
        Fail(cg, d.Loc, "a 'thread' function cannot be generic");
    if (d.IsVariadic)
        Fail(cg, d.Loc, "a 'thread' function cannot be variadic");
    if (fi.Owner != 0 && !d.IsStatic)
        Fail(cg, d.Loc, "'thread' can only be used on a free function or a static method, not an instance method (it cannot see 'this')");
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        var p = d.Params[i];
        if (fi.ParamRefs[i] != 0)
            Fail(cg, p.Loc, "a 'thread' function parameter cannot be 'ref' or 'const ref' ('" + p.Name + "')");
        if (!IsThreadSafeType(cg, fi.ParamTypes[i]))
            Fail(cg, p.Loc, "a 'thread' function parameter must be a plain value type or SharedPtr<T>, not '" + cg.Types.Name(fi.ParamTypes[i]) +
                                "' (parameter '" + p.Name + "')");
    }
}

// A 'thread' function (and everything it calls, directly or not) may never read or write a global variable. Uses the
// call graph that is collected for the check of the initialization order.
void CheckThreadPurity(Compiler cg)
{
    for (var instance = 0; instance < cg.Instances.Count(); instance += 1)
    {
        var fi = cg.Instances.Get(instance);
        if (fi.Entry < 0 || !cg.Funcs.Get(fi.Entry).Decl.IsThread || !fi.Queued)
            continue;
        var loc = cg.Funcs.Get(fi.Entry).Decl.Loc;
        var own = cg.CodeGlobals.TryGet(instance);
        if (own is List<int> used)
        {
            foreach (var g in used)
                ReportThreadGlobal(cg, fi, loc, g, -1);
        }
        var work = List<int>.Create();
        var workVia = List<int>.Create();
        var calls = cg.CodeCalls.TryGet(instance);
        if (calls is List<int> callees)
        {
            foreach (var callee in callees)
            {
                work.Add(callee);
                workVia.Add(callee);
            }
        }
        var seen = HashSet<int>.Create();
        while (work.Count() > 0)
        {
            int last = work.Count() - 1;
            int fn = work.Get(last);
            int via = workVia.Get(last);
            work.RemoveAt(last);
            workVia.RemoveAt(last);
            if (!seen.Add(fn))
                continue;
            var fnGlobals = cg.CodeGlobals.TryGet(fn);
            if (fnGlobals is List<int> fnUsed)
            {
                foreach (var g in fnUsed)
                    ReportThreadGlobal(cg, fi, loc, g, via);
            }
            var fnCalls = cg.CodeCalls.TryGet(fn);
            if (fnCalls is List<int> fnCallees)
            {
                foreach (var callee in fnCallees)
                {
                    work.Add(callee);
                    workVia.Add(via);
                }
            }
        }
    }
}

void ReportThreadGlobal(Compiler cg, FuncInfo fi, SourceLoc loc, int g, int via)
{
    Fail(cg, loc, "'thread' function '" + fi.Name + "' uses the global variable '" + cg.Globals.Get(g).Name + "'" +
                      (via >= 0 ? " (through '" + cg.Instances.Get(via).Name + "')" : "") +
                      "; a thread can only see its parameters and return value");
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

struct ThreadTypes
{
    bool HasResult;
    int Core;      // System._ThreadCore
    int Payload;   // _ThreadCore, or _ThreadControl<T>
    int Handle;    // _ThreadVoid, or Thread<T>
}

int ThreadStruct(Compiler cg, string name, int[] args, SourceLoc loc)
{
    var entry = TypeDeclEntry { };
    if (!LookupTypeDecl(cg, cg.Fn[0].File, name, ref entry) || entry.Kind != DeclKind.Struct)
        Fail(cg, loc, "internal error: '" + name + "' is missing (stdlib/thread.csh not compiled in)");
    return GetStructType(cg, entry.Index, args, loc);
}

ThreadTypes ResolveThreadTypes(Compiler cg, int result, SourceLoc loc)
{
    var tt = ThreadTypes { HasResult = !cg.Types.IsVoid(result) };
    tt.Core = ThreadStruct(cg, "System._ThreadCore", new int[0], loc);
    if (tt.HasResult)
    {
        var args = new int[1];
        args[0] = result;
        tt.Payload = ThreadStruct(cg, "System._ThreadControl", args, loc);
        tt.Handle = ThreadStruct(cg, "System.Thread", args, loc);
    }
    else
    {
        tt.Payload = tt.Core;
        tt.Handle = ThreadStruct(cg, "System._ThreadVoid", new int[0], loc);
    }
    return tt;
}

// A method of a stdlib thread struct (no overloads, not generic).
int ThreadMethod(Compiler cg, int owner, string name, SourceLoc loc)
{
    var cands = MethodCandidates(cg, owner, name);
    if (cands.Length == 0)
        Fail(cg, loc, "internal error: '" + name + "' is missing on '" + cg.Types.Name(owner) + "' (stdlib/thread.csh not compiled in)");
    return GetFuncInstance(cg, cands[0].Entry, cands[0].Owner, GetStructInfo(cg, cands[0].Owner).Env, new int[0], loc);
}

// The thread-local pointer to the control block of the running thread (set by the trampoline, read by Thread.Cancelled).
string CurrentThreadCore(Compiler cg)
{
    string name = "@__cs_thread_current_core";
    if (cg.Ir.Declared.Add(name))
        cg.Ir.Globals.Append(name + " = internal thread_local global ptr null\n");
    return name;
}

void DeclarePthreads(Compiler cg)
{
    cg.Ir.Declare("@malloc", "declare ptr @malloc(i64)");
    cg.Ir.Declare("@pthread_create", "declare i32 @pthread_create(ptr, ptr, ptr, ptr)");
    cg.Ir.Declare("@pthread_detach", "declare i32 @pthread_detach(ptr)");
    cg.Ir.Declare("@pthread_self", "declare ptr @pthread_self()");
}

// The LLVM type of the argument block: { ptr payload, parameters... }.
string ThreadArgsType(Compiler cg, FuncInfo fi)
{
    string text = "{ ptr";
    foreach (var t in fi.ParamTypes)
        text += ", " + LlvmType(cg, t);
    return text + " }";
}

string ThreadTrampolineName(Compiler cg, int instance)
{
    return "@\"__cs_thread_start." + cg.Instances.Get(instance).Name + "." + instance.ToString() + "\"";
}

// ---------------------------------------------------------------------------
// Spawning: 'start f(...)'
// ---------------------------------------------------------------------------

Value EmitThreadSpawn(Compiler cg, int instance, Arg[] args, SourceLoc loc)
{
    var ir = cg.Ir;
    UseFunction(cg, instance);
    NoteCall(cg, instance); // spawning still reaches the function (call graph, purity)
    var fi = cg.Instances.Get(instance);
    if (args.Length != fi.ParamTypes.Length)
        Fail(cg, loc, "'" + fi.Name + "' takes " + fi.ParamTypes.Length.ToString() + " arguments");
    var tt = ResolveThreadTypes(cg, fi.Ret, loc);
    DeclarePthreads(cg);

    // 1. The control block shared with the worker: the layout of SharedPtr<payload>, with two references (the handle
    //    and the worker thread).
    string block = ir.Call("ptr", "@__cs_alloc", "i64 " + SizeOfType(cg, tt.Payload) + ", i64 0");
    ir.Store("i64", "2", block);
    string payload = DataPtr(cg, block);
    EmitDirectCall(cg, ThreadMethod(cg, tt.Core, "Init", loc), payload, new Arg[0], loc);

    // 2. The argument block: the payload and the converted arguments (only plain values and SharedPtr<T>, whose count
    //    is atomic; 'consume' hands the worker a reference of its own). The trampoline frees it.
    string argsType = ThreadArgsType(cg, fi);
    string argsBlock = ir.Call("ptr", "@malloc", "i64 ptrtoint (ptr getelementptr (" + argsType + ", ptr null, i32 1) to i64)");
    EmitPanicIf(cg, ir.ICmp("eq", "ptr", argsBlock, "null"), "out of memory");
    ir.Store("ptr", payload, ir.Gep(argsType, argsBlock, "i32 0, i32 0"));
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        int pt = fi.ParamTypes[i];
        SourceLoc aloc = args[i].Source.IsNull() ? loc : args[i].Source.Loc;
        string value = Consume(cg, ConvertValue(cg, args[i].V, pt, aloc));
        ir.Store(LlvmType(cg, pt), value, ir.Gep(argsType, argsBlock, "i32 0, i32 " + (i + 1).ToString()));
    }

    // 3. Start the OS thread (it detaches itself; Join synchronizes through the condition variable of _ThreadCore).
    if (!cg.TrampolinesQueued.Contains(instance))
    {
        cg.TrampolinesQueued.Add(instance);
        cg.PendingTrampolines.Add(instance);
    }
    string idSlot = ir.Alloca("ptr", "thread.id");
    string rc = ir.Call("i32", "@pthread_create", "ptr " + idSlot + ", ptr null, ptr " + ThreadTrampolineName(cg, instance) + ", ptr " + argsBlock);
    EmitPanicIf(cg, ir.ICmp("ne", "i32", rc, "0"), "cannot create a thread");

    // 4. The caller's reference goes into the handle.
    var wrapArgs = new Arg[1];
    wrapArgs[0].V = Rvalue(cg.Types.SharedPtrOf(tt.Payload), block, true);
    return EmitDirectCall(cg, ThreadMethod(cg, tt.Handle, "_Wrap", loc), "", wrapArgs, loc);
}

// ---------------------------------------------------------------------------
// The trampoline pthread_create calls on the worker thread (one per thread function)
// ---------------------------------------------------------------------------

void EmitThreadTrampoline(Compiler cg, int instance)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var fi = cg.Instances.Get(instance);
    var d = cg.Funcs.Get(fi.Entry).Decl;
    var loc = d.Loc;

    // written like the synthetic functions: the calls it makes are not part of the call graph of any function
    int mark = BeginSyntheticFunctionWith(cg, "define internal ptr " + ThreadTrampolineName(cg, instance) + "(ptr %args)");
    cg.Fn[0].File = fi.File;
    var tt = ResolveThreadTypes(cg, fi.Ret, loc);
    DeclarePthreads(cg);

    ir.Call("i32", "@pthread_detach", "ptr " + ir.Call("ptr", "@pthread_self", ""));
    string argsType = ThreadArgsType(cg, fi);
    string payload = ir.Load("ptr", ir.Gep(argsType, "%args", "i32 0, i32 0"));
    ir.Store("ptr", payload, CurrentThreadCore(cg));

    // The arguments in the block carry a reference of their own: they are passed as owned temporaries and released
    // after the call (the callee retains its own copy).
    var callArgs = new Arg[fi.ParamTypes.Length];
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        int pt = fi.ParamTypes[i];
        string v = ir.Load(LlvmType(cg, pt), ir.Gep(argsType, "%args", "i32 0, i32 " + (i + 1).ToString()));
        callArgs[i].V = Rvalue(pt, v, true);
    }
    ir.Call("void", "@free", "ptr %args");

    Value result = EmitDirectCall(cg, instance, "", callArgs, loc);
    if (tt.HasResult)
    {
        // SetResult stores (and retains) the value; the reference from the call is released with the temporaries.
        var setArgs = new Arg[1];
        setArgs[0].V = result;
        EmitDirectCall(cg, ThreadMethod(cg, tt.Payload, "SetResult", loc), payload, setArgs, loc);
    }
    FlushTemps(cg, 0, true);

    // _ThreadCore is field 0 of _ThreadControl<T>, so the payload is a valid 'this' either way.
    EmitDirectCall(cg, ThreadMethod(cg, tt.Core, "MarkCompleted", loc), payload, new Arg[0], loc);

    // the worker's reference to the control block
    ir.Call("void", ReleaseFunction(cg, types.SharedPtrOf(tt.Payload)), "ptr " + ir.ByteGep(payload, "-16"));
    PopScope(cg, true);
    ir.Ret("ptr", "null");
    ir.EndFunction();
}

// ---------------------------------------------------------------------------
// Thread.Cancelled
// ---------------------------------------------------------------------------

Value EmitThreadCancelled(Compiler cg, SourceLoc loc)
{
    int func = cg.Fn[0].Func;
    var fi = cg.Instances.Get(func);
    if (fi.Entry < 0 || !cg.Funcs.Get(fi.Entry).Decl.IsThread)
        Fail(cg, loc, "'Thread.Cancelled' can only be used inside a 'thread' function");
    string core = cg.Ir.Load("ptr", CurrentThreadCore(cg));
    int coreType = ThreadStruct(cg, "System._ThreadCore", new int[0], loc);
    return EmitDirectCall(cg, ThreadMethod(cg, coreType, "IsCancelled", loc), core, new Arg[0], loc);
}
