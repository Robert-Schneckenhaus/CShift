// Whole-program compilation: from the registered declarations to the text of an LLVM module (port of
// CodeGen::compile and CodeGen::emitEntryPoint).

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// Generates the module for everything that was added with AddUnit and returns its text.
string CompileProgram(Compiler cg, string triple)
{
    // 1. Check 'using' directives.
    for (var i = 0; i < cg.Files.Count(); i += 1)
    {
        var f = cg.Files.Get(i);
        for (var k = 0; k < f.Usings.Count(); k += 1)
        {
            string name = f.Usings.Get(k);
            if (!cg.Namespaces.Contains(name))
                Fail(cg, SourceLoc { File = f.FileId, Line = 1, Col = 1 }, "unknown namespace '" + name + "' in using directive");
        }
    }

    // Every struct of the program is checked (layout, bases), also if nothing uses it.
    for (var s = 0; s < cg.Structs.Count(); s += 1)
    {
        var se = cg.Structs.Get(s);
        if (cg.Files.Get(se.File).IsPrelude || se.Decl.TypeParams.Length > 0)
            continue;
        GetStructType(cg, s, new int[0], se.Decl.Loc);
    }

    // 2. Plain (non-generic, non-method, non-extern) functions of the program are always generated; Main is the entry point.
    int main = -1;
    for (var entry = 0; entry < cg.Funcs.Count(); entry += 1)
    {
        var fe = cg.Funcs.Get(entry);
        var d = fe.Decl;
        if (fe.OwnerStruct != -1 || d.TypeParams.Length > 0 || d.IsExtern)
            continue;
        if (cg.Files.Get(fe.File).IsPrelude)
            continue;
        int instance = GetFuncInstance(cg, entry, 0, NoEnv(), new int[0], d.Loc);
        UseFunction(cg, instance);
        var fi = cg.Instances.Get(instance);
        bool takesArgs = fi.ParamTypes.Length == 1 && fi.ParamTypes[0] == cg.Types.ArrayOf(cg.Types.String) && fi.ParamRefs[0] == 0;
        if (d.Name == "Main" && (d.Params.Length == 0 || takesArgs))
        {
            if (main >= 0)
                Fail(cg, d.Loc, "more than one 'Main' function");
            main = instance;
        }
    }
    if (main < 0)
        Fail(cg, SourceLoc { }, "no entry point: define a function 'int Main()'");
    cg.St[0].MainFunc = main + 1;

    // 3. Generate the function bodies. Calls add work while this runs.
    while (cg.St[0].WorkHead < cg.WorkQueue.Count())
    {
        int instance = cg.WorkQueue.Get(cg.St[0].WorkHead);
        cg.St[0].WorkHead += 1;
        EmitFunctionBody(cg, instance);
    }

    EmitEntryPoint(cg);

    bool windows = cg.St[0].Windows;
    var sb = StringBuilder.Create();
    sb.Append("; cshc\n");
    if (triple.Length > 0)
        sb.Append("target triple = \"" + triple + "\"\n\n");
    sb.Append(RuntimeGlobals(windows, cg.St[0].ArcStats));
    sb.Append(cg.Ir.Globals.ToString());
    sb.Append('\n');
    sb.Append(cg.Ir.Functions.ToString());
    sb.Append(cg.Ir.Helpers.ToString());
    sb.Append(RuntimeFunctions(windows, cg.St[0].ArcStats));
    sb.Append(cg.Ir.Declares.ToString());
    return sb.ToString();
}

// The C entry point 'main' calls Main and returns its result. With --arc-stats it prints the balance of heap blocks.
void EmitEntryPoint(Compiler cg)
{
    var types = cg.Types;
    var ir = cg.Ir;
    var m = cg.Instances.Get(cg.St[0].MainFunc - 1);
    int rt = m.Ret;
    if (!(types.IsVoid(rt) || types.IsInt(rt)))
        Fail(cg, cg.Funcs.Get(m.Entry).Decl.Loc, "'Main' must return void or int (cshc does not support Error<int> yet)");

    // Main(string[] args) gets the arguments without the program name; it only borrows the array.
    string prepare = "";
    string argument = "";
    string cleanup = "";
    if (m.ParamTypes.Length == 1)
    {
        prepare = "  %args = call ptr @__cs_make_args(i32 %argc, ptr %argv)\n";
        argument = "ptr %args";
        cleanup = "  call void " + ReleaseFunction(cg, m.ParamTypes[0]) + "(ptr %args)\n";
    }
    string call;
    string result;
    if (types.IsVoid(rt))
    {
        call = prepare + "  call void " + m.LlvmName + "(" + argument + ")\n" + cleanup;
        result = "  ret i32 0\n";
    }
    else
    {
        call = prepare + "  %r = call " + LlvmType(cg, rt) + " " + m.LlvmName + "(" + argument + ")\n" + cleanup;
        result = ExitCodeConversion(cg, rt);
    }
    string stats = "";
    if (cg.St[0].ArcStats)
    {
        stats = StderrLoad(cg.St[0].Windows) +
                "  %allocs = load i64, ptr @__cs_allocs\n  %frees = load i64, ptr @__cs_frees\n  %live = sub i64 %allocs, %frees\n" +
                "  call i32 (ptr, ptr, ...) @fprintf(ptr %err, ptr @.cs.arc, i64 %allocs, i64 %frees, i64 %live)\n";
    }
    ir.AppendFunctionText("define i32 @main(i32 %argc, ptr %argv) {\nentry:\n" + call + stats + result + "}\n");
}

// Converts the result of Main to the int the C entry point returns.
string ExitCodeConversion(Compiler cg, int rt)
{
    var types = cg.Types;
    int bits = types.Bits(rt);
    if (bits == 32)
        return "  ret i32 %r\n";
    string op = bits > 32 ? "trunc" : (types.IsSigned(rt) ? "sext" : "zext");
    return "  %c = " + op + " " + LlvmType(cg, rt) + " %r to i32\n  ret i32 %c\n";
}
