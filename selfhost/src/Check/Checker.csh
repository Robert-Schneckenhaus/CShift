// The checker: the names and types of every function body, before any code is generated, so that one run reports all
// the errors of a program instead of the first one (docs/semantic-pass.md).
//
// It computes Values like code generation (type, lvalue, const, literal) without code, using the same decisions
// (CodeGen/Rules.csh, ConversionCost, TryResolveOverload) and the same scopes (FnState.Vars). An expression it cannot
// type yet, or one with an error, has the unknown type; nothing involving it is reported, so every mistake gives one
// message. What the checker does not know yet is left to code generation, which still stops at its first error.

namespace CShift.Check;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;
using CShift.CodeGen;

// Checks the bodies of the program's functions and methods (not the standard library, not generic ones yet). Stops
// the compiler if it found errors.
void CheckProgram(Compiler program)
{
    var cg = program;
    // The helpers of code generation that are used here write a little code (a load, a string constant). Module-level
    // output (constants, type definitions, declarations) goes to the real module, because code generation will need it
    // and remembers that it exists; function bodies go to a scratch buffer.
    // The counters (IrState) stay shared, so that the names of new constants are unique; the state of the function
    // being written is restored at the end.
    var ir = program.Ir;
    var saved = ir.S[0];
    ir.Functions = StringBuilder.Create();
    ir.Body = StringBuilder.Create();
    ir.Allocas = StringBuilder.Create();
    ir.Preds = HashSet<string>.Create();
    cg.Ir = ir;
    cg.Fn = new FnState[1];

    int errors = cg.Diag.ErrorCount();
    for (var entry = 0; entry < cg.Funcs.Count(); entry += 1)
    {
        var fe = cg.Funcs.Get(entry);
        var d = fe.Decl;
        if (cg.Files.Get(fe.File).IsPrelude || d.IsExtern || d.Body.IsNull() || d.TypeParams.Length > 0)
            continue;
        int owner = 0;
        var ownerEnv = NoEnv();
        if (fe.OwnerStruct != -1)
        {
            var se = cg.Structs.Get(fe.OwnerStruct);
            if (se.Decl.TypeParams.Length > 0)
                continue;
            owner = GetStructType(cg, fe.OwnerStruct, new int[0], se.Decl.Loc);
            ownerEnv = GetStructInfo(cg, owner).Env;
        }
        CheckFunction(cg, GetFuncInstance(cg, entry, owner, ownerEnv, new int[0], d.Loc));
    }
    int globals = ir.S[0].Global;
    ir.S[0] = saved;
    ir.S[0].Global = globals;
    if (cg.Diag.ErrorCount() > errors)
        Environment.Exit(1);
}

// Reports an error; the checker continues.
void CheckError(Compiler cg, SourceLoc loc, string message)
{
    cg.Diag.ReportAt(loc, message);
}

// A value of the unknown type (not checked further).
Value UnknownValue(Compiler cg)
{
    return Rvalue(cg.Types.Unknown, "", false);
}

bool IsUnknown(Compiler cg, Value v)
{
    return cg.Types.IsUnknown(v.Type);
}

// The body of one function instance, with its parameters in the outermost scope (see EmitFunctionBody).
void CheckFunction(Compiler cg, int instance)
{
    var fi = cg.Instances.Get(instance);
    var d = cg.Funcs.Get(fi.Entry).Decl;
    var f = FnState { Func = instance, RetType = fi.Ret, Checked = true, File = fi.File, Env = fi.Env };
    f.Vars = List<ScopeVar>.Create();
    f.ScopeStarts = List<int>.Create();
    f.Temps = List<TempRelease>.Create();
    f.Loops = List<LoopCtx>.Create();
    f.ThisSlot = fi.HasThis ? "%this" : "";
    cg.Fn[0] = f;
    cg.Ir.BeginFunction("define void @check()");
    PushScope(cg);
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        int pt = fi.ParamTypes[i];
        string name = d.Params[i].Name;
        if (IsInterfaceType(cg, pt))
            cg.Fn[0].Vars.Add(ScopeVar { Name = name, Type = pt, Slot = "%p", IsConst = true });
        else if (fi.ParamRefs[i] != 0)
            cg.Fn[0].Vars.Add(ScopeVar { Name = name, Type = pt, Slot = "%p", IsRef = true, IsConst = fi.ParamRefs[i] == 2 });
        else
            DeclareVar(cg, name, pt, "%p");
    }
    cg.Fn[0].Live = true;
    CheckBlock(cg, d.Body, true);
    // falling off the end (see EmitFunctionBody): the end is reached for sure, so code generation reaches it too
    if (cg.Fn[0].Live && !cg.Types.IsVoid(fi.Ret) && !IsVoidResult(cg, fi.Ret))
        CheckError(cg, d.Loc, "not all code paths of '" + fi.Name + "' return a value");
    PopScope(cg, false);
    cg.Ir.EndFunction();
}
