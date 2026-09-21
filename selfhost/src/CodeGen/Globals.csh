// Global variables (port of the global parts of CodeGen: lookupGlobal, globalValue, emitGlobalsInit and
// emitGlobalsRelease).
//
//     int Counter;                                   starts with 0
//     List<string> Names = List<string>.Create();    any expression
//
// A global is an LLVM variable. Initializers run before Main in the order of the declarations (files in the order they
// were given to the compiler); values that own heap blocks are released again when Main has returned.

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

// The code that gives the globals their initial values: a function that the entry point calls before Main.
void EmitGlobalsInit(Compiler cg)
{
    var types = cg.Types;
    var ir = cg.Ir;
    bool any = false;
    for (var i = 0; i < cg.Globals.Count(); i += 1)
        any = any || !cg.Globals.Get(i).Decl.Init.IsNull();
    if (!any)
        return;

    // the function looks like a function without parameters to the code generator
    var info = FuncInfo { Entry = -1, File = 0, Owner = 0, Name = "global initializers", Ret = types.Void, LlvmName = "@__cs_init_globals",
                          SignatureResolved = true, Queued = true };
    info.Env = NoEnv();
    info.ParamTypes = new int[0];
    info.ParamRefs = new int[0];
    cg.Instances.Add(info);

    var f = FnState { Func = cg.Instances.Count() - 1, RetType = types.Void, Checked = true, File = 0, Env = NoEnv() };
    f.Vars = List<ScopeVar>.Create();
    f.ScopeStarts = List<int>.Create();
    f.Temps = List<TempRelease>.Create();
    f.Loops = List<LoopCtx>.Create();
    cg.Fn[0] = f;
    ir.BeginFunction("define internal void @__cs_init_globals()");
    PushScope(cg);
    for (var i = 0; i < cg.Globals.Count(); i += 1)
    {
        var g = cg.Globals.Get(i);
        if (g.Decl.Init.IsNull())
            continue;
        cg.Fn[0].File = g.File;
        PushScope(cg); // the scope of pattern variables in the initializer
        Value target = GlobalValue(cg, i);
        var current = cg.Globals.Get(i);
        Value v = ConvertValue(cg, EmitExpr(cg, g.Decl.Init), current.Type, g.Decl.Init.Loc);
        StoreSlot(cg, current.Type, target.V, Consume(cg, v), false);
        FlushTemps(cg, 0, true);
        PopScope(cg, true);
    }
    PopScope(cg, true);
    ir.Ret("void", "");
    ir.EndFunction();
    cg.St[0].HasGlobalsInit = true;
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
