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

// Checks the bodies of the program's functions and methods (not the standard library; generic ones once, see below).
// Stops the compiler if it or the declarations before it found errors.
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

    CheckGlobalInitializers(cg);

    for (var entry = 0; entry < cg.Funcs.Count(); entry += 1)
    {
        var fe = cg.Funcs.Get(entry);
        var d = fe.Decl;
        if (cg.Files.Get(fe.File).IsPrelude || d.IsExtern || d.Body.IsNull())
            continue;
        int owner = 0;
        var ownerEnv = NoEnv();
        if (fe.OwnerStruct != -1)
        {
            var se = cg.Structs.Get(fe.OwnerStruct);
            if (se.Decl.TypeParams.Length > 0)
            {
                // a method of a generic struct: checked once, with the checker's instance of the struct
                owner = GetCheckingStructType(cg, fe.OwnerStruct);
                if (GetStructInfo(cg, owner).UnknownBase)
                    continue; // its inherited fields are not known (a generic base)
            }
            else
                owner = GetStructType(cg, fe.OwnerStruct, new int[0], se.Decl.Loc);
            ownerEnv = GetStructInfo(cg, owner).Env;
        }
        // a generic function is checked once: its type parameters are the unknown type, so what depends on them is left
        // to each instantiation (code generation), and everything else is checked here
        var typeArgs = new int[d.TypeParams.Length];
        for (var i = 0; i < typeArgs.Length; i += 1)
            typeArgs[i] = cg.Types.Unknown;
        CheckFunction(cg, GetFuncInstance(cg, entry, owner, ownerEnv, typeArgs, d.Loc));
    }
    int globals = ir.S[0].Global;
    ir.S[0] = saved;
    ir.S[0].Global = globals;
    // also for the errors of the declarations: the program is not generated after an error ('check'/'query' go on to
    // answer and set the exit code themselves)
    if (cg.Diag.ErrorCount() > 0 && !cg.St[0].FrontEndOnly)
        Environment.Exit(1);
}

// Reports an error; the checker continues. A message that names the unknown type follows from an error that was
// reported before (where the type is written), so it is left out.
void CheckError(Compiler cg, SourceLoc loc, string message)
{
    if (message.Contains(UnknownTypeName))
        return;
    if (cg.St[0].Muted)
    {
        if (cg.St[0].MutedError.Length == 0)
            cg.St[0].MutedError = message;
        return;
    }
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
        NoteVar(cg, d.Params[i].Loc, true);
    }
    cg.Fn[0].Live = true;
    CheckBlock(cg, d.Body, true);
    // falling off the end (see EmitFunctionBody): the end is reached for sure, so code generation reaches it too
    if (cg.Fn[0].Live && !cg.Types.IsVoid(fi.Ret) && !IsVoidResult(cg, fi.Ret))
        CheckError(cg, d.Loc, "not all code paths of '" + DisplayName(cg, instance) + "' return a value");
    PopScope(cg, false);
    cg.Ir.EndFunction();
}

// The initializers of the program's globals (see EmitGlobalsInit): each one in its own scope, converted to the type of
// its global.
void CheckGlobalInitializers(Compiler cg)
{
    for (var i = 0; i < cg.Globals.Count(); i += 1)
    {
        var g = cg.Globals.Get(i);
        if (g.Decl.Init.IsNull() || cg.Files.Get(g.File).IsPrelude)
            continue;
        Value target = GlobalValue(cg, i);
        var f = FnState { Func = SyntheticInstance(cg), RetType = cg.Types.Void, Checked = true, File = g.File, Env = NoEnv() };
        f.Vars = List<ScopeVar>.Create();
        f.ScopeStarts = List<int>.Create();
        f.Temps = List<TempRelease>.Create();
        f.Loops = List<LoopCtx>.Create();
        f.ThisSlot = "";
        f.Live = true;
        cg.Fn[0] = f;
        cg.Ir.BeginFunction("define void @check()");
        PushScope(cg); // the scope of pattern variables in the initializer
        CheckConversion(cg, CheckExpr(cg, g.Decl.Init), target.Type, g.Decl.Init.Loc);
        PopScope(cg, false);
        cg.Ir.EndFunction();
    }
}

// The name of a function instance in messages. The checker's instances of generic functions and of the methods of
// generic structs show their type parameters ('Max<T>', 'Box<T>.Get'), not the unknown type.
string DisplayName(Compiler cg, int instance)
{
    var fi = cg.Instances.Get(instance);
    if (!fi.Name.Contains(UnknownTypeName))
        return fi.Name;
    var d = cg.Funcs.Get(fi.Entry).Decl;
    string name = d.Name + TypeParamList(d.TypeParams);
    if (fi.Owner != 0)
    {
        var sd = cg.Structs.Get(GetStructInfo(cg, fi.Owner).Entry).Decl;
        name = sd.Name + TypeParamList(sd.TypeParams) + "." + name;
    }
    return name;
}

string TypeParamList(string[] names)
{
    if (names.Length == 0)
        return "";
    return "<" + string.Join(", ", names) + ">";
}
