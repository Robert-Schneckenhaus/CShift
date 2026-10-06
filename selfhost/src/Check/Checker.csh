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

    // the constants of the program where they are declared (their values were computed by CheckConstants)
    for (var c = 0; c < cg.Consts.Count() && cg.St[0].Indexing; c += 1)
    {
        var ce = cg.Consts.Get(c);
        if (!cg.Files.Get(ce.File).IsPrelude)
            IndexConst(cg, ce.Decl.Loc, ce.Decl.Name.Length, c);
    }

    CheckGlobalInitializers(cg);

    for (var entry = 0; entry < cg.Funcs.Count(); entry += 1)
    {
        var fe = cg.Funcs.Get(entry);
        var d = fe.Decl;
        if (cg.Files.Get(fe.File).IsPrelude || d.Body.IsNull())
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
void CheckError(const ref Compiler cg, SourceLoc loc, string message)
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
Value UnknownValue(const ref Compiler cg)
{
    return Rvalue(cg.Types.Unknown, "", false);
}

bool IsUnknown(const ref Compiler cg, Value v)
{
    return cg.Types.IsUnknown(v.Type);
}

// The body of one function instance, with its parameters in the outermost scope (see EmitFunctionBody).
void CheckFunction(const ref Compiler cg, int instance)
{
    var fi = cg.Instances.Get(instance);
    var d = cg.Funcs.Get(fi.Entry).Decl;
    var f = FnState { Func = instance, RetType = fi.Ret, Checked = CheckedByDefault(cg, fi.File), File = fi.File, Env = fi.Env };
    f.Vars = List<ScopeVar>.Create();
    f.ScopeStarts = List<int>.Create();
    f.Temps = List<TempRelease>.Create();
    f.Loops = List<LoopCtx>.Create();
    f.ThisSlot = fi.HasThis ? "%this" : "";
    // a generic body: the methods that its type parameters offer are those of their constraints (TypeParamMethodError)
    var names = List<string>.Create();
    var constraints = List<Constraint>.Create();
    foreach (var tp in d.TypeParams)
        names.Add(tp);
    foreach (var c in d.Constraints)
        constraints.Add(c);
    if (fi.Owner != 0 && cg.Types.IsStruct(fi.Owner))
    {
        var od = cg.Structs.Get(GetStructInfo(cg, fi.Owner).Entry).Decl;
        foreach (var tp in od.TypeParams)
            names.Add(tp);
        foreach (var c in od.Constraints)
            constraints.Add(c);
    }
    f.Generic = names.Count() > 0;
    f.TypeParamNames = names.ToArray();
    f.TypeParamConstraints = constraints.ToArray();
    f.TypeParamVars = List<string>.Create();
    cg.Fn[0] = f;
    cg.Ir.BeginFunction("define void @check()");
    PushScope(cg);
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        int pt = fi.ParamTypes[i];
        string name = d.Params[i].Name;
        CheckNotDeclared(cg, d.Params[i].NameLoc.Line > 0 ? d.Params[i].NameLoc : d.Params[i].Loc, name);
        if (IsInterfaceType(cg, pt))
            cg.Fn[0].Vars.Add(ScopeVar { Name = name, Type = pt, Slot = "%p", IsConst = true });
        else if (fi.ParamRefs[i] != 0)
            cg.Fn[0].Vars.Add(ScopeVar { Name = name, Type = pt, Slot = "%p", IsRef = true, IsConst = fi.ParamRefs[i] == 2 });
        else
            DeclareVar(cg, name, pt, "%p");
        NoteDeclared(cg, d.Params[i].NameLoc, d.Params[i].Loc, true, d.Params[i].Type, d.Params[i].Ref);
        NoteTypeParamVar(cg, name, d.Params[i].Type);
    }
    if (d.NameLoc.Line > 0)
        IndexFunction(cg, d.NameLoc, d.Name.Length, instance); // the name where the function is declared
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
void CheckGlobalInitializers(const ref Compiler cg)
{
    for (var i = 0; i < cg.Globals.Count(); i += 1)
    {
        var g = cg.Globals.Get(i);
        if (g.Decl.Init.IsNull() || cg.Files.Get(g.File).IsPrelude)
            continue;
        Value target = GlobalValue(cg, i);
        var f = FnState { Func = SyntheticInstance(cg), RetType = cg.Types.Void, Checked = CheckedByDefault(cg, g.File), File = g.File, Env = NoEnv() };
        f.Vars = List<ScopeVar>.Create();
        f.ScopeStarts = List<int>.Create();
        f.Temps = List<TempRelease>.Create();
        f.Loops = List<LoopCtx>.Create();
        f.ThisSlot = "";
        f.Live = true;
        cg.Fn[0] = f;
        cg.Ir.BeginFunction("define void @check()");
        PushScope(cg); // the scope of pattern variables in the initializer
        CheckConversion(cg, CheckExprAs(cg, g.Decl.Init, target.Type), target.Type, cg.Tree.StartOf(g.Decl.Init));
        PopScope(cg, false);
        cg.Ir.EndFunction();
    }
}

// The name of a function instance in messages. The checker's instances of generic functions and of the methods of
// generic structs show their type parameters ('Max<T>', 'Box<T>.Get'), not the unknown type.
string DisplayName(const ref Compiler cg, int instance)
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

// In a generic body: remembers that the variable 'name' has the type parameter its declared type names (or forgets it).
void NoteTypeParamVar(const ref Compiler cg, string name, TypeRef declared)
{
    var f = cg.Fn[0];
    if (!f.Generic)
        return;
    for (var i = f.TypeParamVars.Count() - 1; i >= 0; i -= 1)
    {
        if (f.TypeParamVars.Get(i).StartsWith(name + "="))
            f.TypeParamVars.RemoveAt(i);
    }
    if (declared.IsNull())
        return;
    var node = cg.Tree.GetType(declared);
    if (node.Kind != TypeRefKind.Named || node.Path.Length != 1 || node.Args.Length > 0)
        return;
    foreach (var tp in f.TypeParamNames)
    {
        if (tp == node.Path[0])
            f.TypeParamVars.Add(name + "=" + tp);
    }
}

// In a generic body, a method call on a variable whose type is a type parameter: "" if one of the constraints of the
// type parameter has the method (or it cannot be told), otherwise the error. Every type has ToString.
string TypeParamMethodError(const ref Compiler cg, string variable, string method)
{
    var f = cg.Fn[0];
    if (!f.Generic || method == "ToString")
        return "";
    string tp = "";
    foreach (var entry in f.TypeParamVars)
    {
        if (entry.StartsWith(variable + "="))
            tp = entry.Substring(variable.Length + 1).ToString();
    }
    if (tp.Length == 0)
        return "";
    var bounds = List<string>.Create();
    foreach (var c in f.TypeParamConstraints)
    {
        if (c.Param != tp)
            continue;
        foreach (var b in c.Bounds)
        {
            var node = cg.Tree.GetType(b);
            if (node.Kind != TypeRefKind.Named)
                return "";
            var decl = TypeDeclEntry { };
            if (!LookupTypeDecl(cg, f.File, string.Join(".", node.Path), ref decl) || decl.Kind != DeclKind.Interface)
                return "";
            foreach (var m in cg.Interfaces.Get(decl.Index).Decl.Methods)
            {
                if (m.Name == method)
                    return "";
            }
            bounds.Add(cg.Tree.TypeToString(b));
        }
    }
    if (bounds.Count() == 0)
        return "'" + variable + "' has the type parameter '" + tp + "', which has no method '" + method + "': a type parameter " +
               "only offers the methods of its constraints, and '" + tp + "' has none (add 'where " + tp + " : I...')";
    return "'" + variable + "' has the type parameter '" + tp + "', which has no method '" + method + "': a type parameter " +
           "only offers the methods of its constraints ('" + tp + " : " + string.Join(", ", bounds.ToArray()) + "')";
}
