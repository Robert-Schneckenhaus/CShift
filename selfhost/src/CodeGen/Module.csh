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

    for (var en = 0; en < cg.Enums.Count(); en += 1)
    {
        if (!cg.Files.Get(cg.Enums.Get(en).File).IsPrelude)
            GetEnumType(cg, en);
    }

    CheckConstants(cg);

    // The globals of the program are checked even if nothing uses them; their initializers run before Main.
    for (var gi = 0; gi < cg.Globals.Count(); gi += 1)
    {
        if (!cg.Files.Get(cg.Globals.Get(gi).File).IsPrelude)
            GlobalValue(cg, gi);
    }
    EmitGlobalsInit(cg);

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
    while (cg.St[0].WorkHead < cg.WorkQueue.Count() || cg.PendingVerify.Count() > 0 || cg.PendingTrampolines.Count() > 0)
    {
        while (cg.PendingVerify.Count() > 0)
        {
            int last = cg.PendingVerify.Count() - 1;
            int pending = cg.PendingVerify.Get(last);
            cg.PendingVerify.RemoveAt(last);
            VerifyStruct(cg, pending);
        }
        if (cg.St[0].WorkHead < cg.WorkQueue.Count())
        {
            int instance = cg.WorkQueue.Get(cg.St[0].WorkHead);
            cg.St[0].WorkHead += 1;
            EmitFunctionBody(cg, instance);
        }
        else if (cg.PendingTrampolines.Count() > 0)
        {
            int threadFunc = cg.PendingTrampolines.Get(0);
            cg.PendingTrampolines.RemoveAt(0);
            EmitThreadTrampoline(cg, threadFunc);
        }
    }

    CheckThreadPurity(cg);
    CheckGlobalInitOrder(cg);
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
    sb.Append(RuntimeFunctions(windows, cg.St[0].ArcStats, cg.Ir));
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
    bool okRet = types.IsVoid(rt) || types.IsInt(rt) || (types.IsError(rt) && types.IsInt(types.Elem(rt)));
    if (!okRet)
        Fail(cg, cg.Funcs.Get(m.Entry).Decl.Loc, "'Main' must return void, int or Error<int>");

    // Main(string[] args) gets the arguments without the program name; it only borrows the array.
    string prepare = cg.St[0].HasGlobalsInit ? "  call void @__cs_init_globals()\n" : "";
    string argument = "";
    string cleanup = "";
    // the values of the globals are released when Main has returned (before the balance of heap blocks is printed)
    string releaseGlobals = EmitGlobalsRelease(cg) ? "  call void @__cs_release_globals()\n" : "";
    if (m.ParamTypes.Length == 1)
    {
        prepare += "  %args = call ptr @__cs_make_args(i32 %argc, ptr %argv)\n";
        argument = "ptr %args";
        cleanup = "  call void " + ReleaseFunction(cg, m.ParamTypes[0]) + "(ptr %args)\n";
    }

    // Returns from main; with --arc-stats the heap block balance is printed first.
    string stats = releaseGlobals + ArcStatsCode(cg, "");
    string body;
    if (types.IsVoid(rt))
    {
        body = prepare + "  call void " + m.LlvmName + "(" + argument + ")\n" + cleanup + stats + "  ret i32 0\n";
    }
    else if (types.IsInt(rt))
    {
        body = prepare + "  %r = call " + LlvmType(cg, rt) + " " + m.LlvmName + "(" + argument + ")\n" + cleanup + stats +
               ExitCodeConversion(cg, rt, "%r");
    }
    else
    {
        // Error<int>: the payload is the exit code, an error is printed and gives exit code 1
        int elem = types.Elem(rt);
        string ty = LlvmType(cg, rt);
        body = prepare + "  %r = call " + ty + " " + m.LlvmName + "(" + argument + ")\n" + cleanup +
               "  %isok = extractvalue " + ty + " %r, 0\n  br i1 %isok, label %ok, label %fail\n" +
               "ok:\n  %v = extractvalue " + ty + " %r, 1\n" + releaseGlobals + ArcStatsCode(cg, ".ok") +
               ExitCodeConversion(cg, elem, "%v") +
               "fail:\n  %msg = extractvalue " + ty + " %r, 2\n  %text = call ptr @__cs_data(ptr %msg)\n" +
               StderrLoad(cg.St[0].Windows).Replace("%err", "%err.msg") +
               "  call i32 (ptr, ptr, ...) @fprintf(ptr %err.msg, ptr " + ir.CString("error: %s\n") + ", ptr %text)\n" +
               stats + "  ret i32 1\n";
    }
    ir.AppendFunctionText("define i32 @main(i32 %argc, ptr %argv) {\nentry:\n" + body + "}\n");
}

// Converts the result of Main (in the register 'value') to the int the C entry point returns.
string ExitCodeConversion(Compiler cg, int rt, string value)
{
    var types = cg.Types;
    int bits = types.Bits(rt);
    if (bits == 32)
        return "  ret i32 " + value + "\n";
    string op = bits > 32 ? "trunc" : (types.IsSigned(rt) ? "sext" : "zext");
    return "  %c = " + op + " " + LlvmType(cg, rt) + " " + value + " to i32\n  ret i32 %c\n";
}

// The code that prints the balance of heap blocks (--arc-stats); the suffix keeps the register names unique.
string ArcStatsCode(Compiler cg, string suffix)
{
    if (!cg.St[0].ArcStats)
        return "";
    string a = "%allocs" + suffix;
    string f = "%frees" + suffix;
    string l = "%live" + suffix;
    string e = "%err" + suffix;
    return StderrLoad(cg.St[0].Windows).Replace("%err", e) +
           "  " + a + " = load i64, ptr @__cs_allocs\n  " + f + " = load i64, ptr @__cs_frees\n  " + l + " = sub i64 " + a + ", " + f + "\n" +
           "  call i32 (ptr, ptr, ...) @fprintf(ptr " + e + ", ptr @.cs.arc, i64 " + a + ", i64 " + f + ", i64 " + l + ")\n";
}
