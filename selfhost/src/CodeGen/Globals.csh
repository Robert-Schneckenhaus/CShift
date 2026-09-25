// Global variables and constants (port of the global parts of CodeGen: lookupGlobal, globalValue, emitGlobalsInit,
// emitGlobalsRelease, checkGlobalInitOrder and checkConstants).
//
//     int Counter;                                   starts with 0
//     List<string> Names = List<string>.Create();    any expression
//
// A global is an LLVM variable. Initializers run before Main in the order of the declarations (files in the order they
// were given to the compiler); values that own heap blocks are released again when Main has returned. After all
// function bodies are written it is checked that no initializer needs a global that is initialized later.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

struct GlobalEntry
{
    GlobalDecl Decl;
    int File;           // index in Compiler.Files
    string Name;        // qualified
    int Type;           // 0 until the variable is created
    string Var;         // the LLVM variable, e.g. @"global.Ns.Counter"
}

// The global a name refers to (looked up like a constant), or -1.
int LookupGlobal(Compiler cg, int file, string name)
{
    foreach (var c in CandidateNames(cg, file, name))
    {
        var found = cg.GlobalDecls.TryGet(c);
        if (found is int index)
            return index;
    }
    return -1;
}

// The variable of a global as an lvalue. Its type and the LLVM variable are created on first use.
Value GlobalValue(Compiler cg, int index)
{
    var types = cg.Types;
    var g = cg.Globals.Get(index);
    if (g.Type == 0)
    {
        int t = ResolveValueType(cg, g.Decl.Type.Id, g.File, NoEnv());
        if (types.IsVoid(t))
            Fail(cg, g.Decl.Loc, "variable '" + g.Name + "' cannot have type 'void'");
        if (types.IsStruct(t) && GetStructInfo(cg, t).Opaque)
            Fail(cg, g.Decl.Loc, "'" + types.Name(t) + "' is an incomplete C type and can only be used through a pointer ('" + types.Name(t) + "*')");
        g.Type = t;
        g.Var = "@\"global." + g.Name + "\"";
        cg.Globals.Set(index, g);
        cg.CreatedGlobals.Add(index);
        cg.Ir.Globals.Append(g.Var + " = internal global " + LlvmType(cg, t) + " zeroinitializer\n");
    }
    return Lvalue(g.Type, g.Var, false);
}

// The variable of a global that the code being written uses (recorded for the check of the initialization order).
Value GlobalUse(Compiler cg, int index)
{
    NoteGlobalUse(cg, index);
    return GlobalValue(cg, index);
}

// ---------------------------------------------------------------------------
// What the code uses: for the check of the initialization order
// ---------------------------------------------------------------------------

int NoCodeKey()
{
    return -2000000000;
}

// The key of the code that is being written: the function instance, or -1 - g for the initializer of global g.
int CurrentCodeKey(Compiler cg)
{
    int func = cg.Fn[0].Func;
    if (cg.St[0].InitInstance != 0 && func == cg.St[0].InitInstance - 1)
        return cg.St[0].InitActive ? -1 - cg.St[0].CurrentInit : NoCodeKey();
    return func;
}

void AddUse(Dictionary<int, List<int>> map, int key, int value)
{
    var found = map.TryGet(key);
    if (found is List<int> list)
    {
        list.Add(value);
        return;
    }
    var fresh = List<int>.Create();
    fresh.Add(value);
    map.Set(key, fresh);
}

void NoteGlobalUse(Compiler cg, int index)
{
    int key = CurrentCodeKey(cg);
    if (key != NoCodeKey())
        AddUse(cg.CodeGlobals, key, index);
}

// The code being written calls the function instance (or takes its address: it can be called through the pointer later).
void NoteCall(Compiler cg, int instance)
{
    int key = CurrentCodeKey(cg);
    if (key != NoCodeKey())
        AddUse(cg.CodeCalls, key, instance);
}

void ReportInitOrder(Compiler cg, int g, int h, int via, HashSet<int> reported)
{
    var gd = cg.Globals.Get(g);
    var hd = cg.Globals.Get(h);
    if (h < g || hd.Decl.Init.IsNull() || !reported.Add(h))
        return;
    string message = "the initializer of global '" + gd.Name + "' uses global '" + hd.Name + "'" +
                     (via >= 0 ? " (through '" + cg.Instances.Get(via).Name + "')" : "") + " before it is initialized";
    message += h == g ? " (a global cannot use itself in its own initializer)" : "; declare '" + hd.Name + "' before '" + gd.Name + "'";
    Fail(cg, gd.Decl.Loc, message);
}

// An initializer must not use a global that is initialized later (or itself): the value would still be zero. The code the
// initializer calls counts as well, so the functions it reaches (directly or through other functions) are searched.
void CheckGlobalInitOrder(Compiler cg)
{
    for (var g = 0; g < cg.Globals.Count(); g += 1)
    {
        if (cg.Globals.Get(g).Decl.Init.IsNull())
            continue;
        var reported = HashSet<int>.Create();
        int key = -1 - g;
        var direct = cg.CodeGlobals.TryGet(key);
        if (direct is List<int> used)
        {
            foreach (var h in used)
                ReportInitOrder(cg, g, h, -1, reported);
        }
        var calls = cg.CodeCalls.TryGet(key);
        var callees = List<int>.Create();
        if (calls is List<int> direct2)
            callees = direct2;
        // the functions the initializer calls; 'via' is the function the initializer calls directly
        var work = List<int>.Create();
        var workVia = List<int>.Create();
        foreach (var callee in callees)
        {
            work.Add(callee);
            workVia.Add(callee);
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
                foreach (var h in fnUsed)
                    ReportInitOrder(cg, g, h, via, reported);
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

// ---------------------------------------------------------------------------
// Functions that only exist for the code generator
// ---------------------------------------------------------------------------

// Starts a function without parameters: the initializers of the globals (kept) and the check of the constants
// (dropped). Its code is written with the normal expression and statement code. Returns where the function starts in
// the output, to be able to drop it again.
int BeginSyntheticFunction(Compiler cg, string name)
{
    return BeginSyntheticFunctionWith(cg, "define internal void @" + name + "()");
}

// The same with any function header (the thread trampolines).
int BeginSyntheticFunctionWith(Compiler cg, string header)
{
    var types = cg.Types;
    if (cg.St[0].InitInstance == 0)
    {
        // the function looks like a function without parameters to the code generator
        var info = FuncInfo { Entry = -1, File = 0, Owner = 0, Name = "global initializers", Ret = types.Void, LlvmName = "@__cs_init_globals",
                              SignatureResolved = true, Queued = true };
        info.Env = NoEnv();
        info.ParamTypes = new int[0];
        info.ParamRefs = new int[0];
        cg.Instances.Add(info);
        cg.St[0].InitInstance = cg.Instances.Count();
    }
    var f = FnState { Func = cg.St[0].InitInstance - 1, RetType = types.Void, Checked = true, File = 0, Env = NoEnv() };
    f.Vars = List<ScopeVar>.Create();
    f.ScopeStarts = List<int>.Create();
    f.Temps = List<TempRelease>.Create();
    f.Loops = List<LoopCtx>.Create();
    cg.Fn[0] = f;
    int mark = cg.Ir.Functions.Length();
    cg.Ir.BeginFunction(header);
    PushScope(cg);
    return mark;
}

void EndSyntheticFunction(Compiler cg, int mark, bool keep)
{
    PopScope(cg, true);
    cg.Ir.Ret("void", "");
    cg.Ir.EndFunction();
    if (!keep)
        cg.Ir.Functions.Truncate(mark);
}

// The code that gives the globals their initial values: a function that the entry point calls before Main.
void EmitGlobalsInit(Compiler cg)
{
    bool any = false;
    for (var i = 0; i < cg.Globals.Count(); i += 1)
        any = any || !cg.Globals.Get(i).Decl.Init.IsNull();
    if (!any)
        return;

    int mark = BeginSyntheticFunction(cg, "__cs_init_globals");
    for (var i = 0; i < cg.Globals.Count(); i += 1)
    {
        var g = cg.Globals.Get(i);
        if (g.Decl.Init.IsNull())
            continue;
        cg.Fn[0].File = g.File;
        PushScope(cg); // the scope of pattern variables in the initializer
        Value target = GlobalValue(cg, i);
        var current = cg.Globals.Get(i);
        cg.St[0].CurrentInit = i;
        cg.St[0].InitActive = true;
        Value v = ConvertValue(cg, EmitExpr(cg, g.Decl.Init), current.Type, g.Decl.Init.Loc);
        StoreSlot(cg, current.Type, target.V, Consume(cg, v), false);
        FlushTemps(cg, 0, true);
        cg.St[0].InitActive = false;
        PopScope(cg, true);
    }
    EndSyntheticFunction(cg, mark, true);
    cg.St[0].HasGlobalsInit = true;
}

// The constants of the program are checked even if nothing uses them: type, initializer and value.
void CheckConstants(Compiler cg)
{
    for (var i = 0; i < cg.Consts.Count(); i += 1)
    {
        if (!cg.Files.Get(cg.Consts.Get(i).File).IsPrelude)
            ConstEvalDecl(cg, i);
    }
}

// The function that releases the values of the globals at the end of the program, so that no heap block is left over.
// Returns false if no global owns anything.
bool EmitGlobalsRelease(Compiler cg)
{
    var text = StringBuilder.Create();
    text.Append("define internal void @__cs_release_globals() {\nentry:\n");
    bool any = false;
    foreach (var index in cg.CreatedGlobals)
    {
        var g = cg.Globals.Get(index);
        if (!NeedsArc(cg, g.Type))
            continue;
        string ty = LlvmType(cg, g.Type);
        string reg = "%g" + index.ToString();
        text.Append("  " + reg + " = load " + ty + ", ptr " + g.Var + "\n");
        text.Append("  call void " + ReleaseFunction(cg, g.Type) + "(" + ty + " " + reg + ")\n");
        any = true;
    }
    if (!any)
        return false;
    text.Append("  ret void\n}\n");
    cg.Ir.AppendFunctionText(text.ToString());
    return true;
}
