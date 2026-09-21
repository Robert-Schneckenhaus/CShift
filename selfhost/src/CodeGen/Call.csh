// Calls (port of CodeGenCall.cpp): argument handling, overload resolution, calls of functions and of the builtin
// static functions (Console, Environment).

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// An evaluated argument: its value and the expression it came from (for error positions).
struct Arg
{
    Value V;
    Expr Source;
}

Arg[] EmitArgs(Compiler cg, Expr[] args)
{
    var list = new Arg[args.Length];
    for (var i = 0; i < args.Length; i += 1)
        list[i] = Arg { Source = args[i], V = EmitExpr(cg, args[i]) };
    return list;
}

// The cost of passing an argument to a parameter (-1 = impossible).
int ArgCost(Compiler cg, Arg arg, int paramType, int refKind)
{
    var v = arg.V;
    var types = cg.Types;
    switch (refKind)
    {
    case 0:
        if (v.IsRefArg)
            return -1;
        return ConversionCost(cg, v, paramType);
    case 1:
        if (!v.IsRefArg || !v.IsLValue || v.IsConst)
            return -1;
        return v.Type == paramType ? 0 : -1;
    default:
        if (v.IsLValue && v.Type == paramType)
            return 0;
        int c = ConversionCost(cg, v, paramType);
        return c < 0 ? -1 : c + 1;
    }
}

// Chooses the function that matches the arguments best. Candidates are indices in Compiler.Funcs.
int ResolveOverload(Compiler cg, int[] candidates, Arg[] args, SourceLoc loc, string name)
{
    var best = -1;
    int bestCost = 0;
    bool ambiguous = false;
    string reason = "";

    foreach (var entry in candidates)
    {
        var d = cg.Funcs.Get(entry).Decl;
        if (d.TypeParams.Length > 0)
            Fail(cg, loc, "cshc does not support generic functions yet ('" + name + "')");
        if (args.Length < d.Params.Length || (!d.IsVariadic && args.Length != d.Params.Length))
        {
            reason = "expected " + d.Params.Length.ToString() + " argument(s), got " + args.Length.ToString();
            continue;
        }

        int instance = GetFuncInstance(cg, entry, 0, NoEnv(), new int[0], loc);
        var fi = cg.Instances.Get(instance);

        int total = 0;
        bool ok = true;
        for (var i = 0; i < fi.ParamTypes.Length; i += 1)
        {
            int cost = ArgCost(cg, args[i], fi.ParamTypes[i], fi.ParamRefs[i]);
            if (cost < 0)
            {
                string prefix = fi.ParamRefs[i] == 1 ? "ref " : (fi.ParamRefs[i] == 2 ? "const ref " : "");
                reason = "argument " + (i + 1).ToString() + ": cannot convert '" + cg.Types.Name(args[i].V.Type) + "' to '" + prefix +
                         cg.Types.Name(fi.ParamTypes[i]) + "'";
                if (fi.ParamRefs[i] == 1 && !args[i].V.IsRefArg)
                    reason += " (pass it with 'ref')";
                ok = false;
                break;
            }
            total += cost;
        }
        for (var i = fi.ParamTypes.Length; ok && i < args.Length; i += 1)
            if (args[i].V.IsRefArg)
                ok = false;
        if (!ok)
            continue;

        int score = total * 2;
        if (best < 0 || score < bestCost)
        {
            best = instance;
            bestCost = score;
            ambiguous = false;
        }
        else if (score == bestCost && instance != best)
        {
            ambiguous = true;
        }
    }

    if (best < 0)
    {
        var sb = StringBuilder.Create();
        sb.Append("no matching function for call '" + name + "(");
        for (var i = 0; i < args.Length; i += 1)
        {
            if (i > 0)
                sb.Append(", ");
            if (args[i].V.IsRefArg)
                sb.Append("ref ");
            sb.Append(cg.Types.Name(args[i].V.Type));
        }
        sb.Append(")'");
        if (reason.Length > 0)
            sb.Append(": " + reason);
        Fail(cg, loc, sb.ToString());
    }
    if (ambiguous)
        Fail(cg, loc, "the call to '" + name + "' is ambiguous");
    return best;
}

// Emits the call of a function instance with the given (already evaluated) arguments.
Value EmitDirectCall(Compiler cg, int instance, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    UseFunction(cg, instance);
    var fi = cg.Instances.Get(instance);
    var d = cg.Funcs.Get(fi.Entry).Decl;
    if (fi.HasThis)
        Fail(cg, loc, "cshc does not support methods yet");

    var callArgs = StringBuilder.Create();
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        var a = args[i];
        int pt = fi.ParamTypes[i];
        SourceLoc aloc = a.Source.IsNull() ? loc : a.Source.Loc;
        string passed;
        string passedType;
        if (fi.ParamRefs[i] == 0)
        {
            Value cv = ConvertValue(cg, a.V, pt, aloc);
            HoldTemp(cg, cv);
            passed = cv.V;
            passedType = LlvmType(cg, pt);
        }
        else if (fi.ParamRefs[i] == 1)
        {
            passed = a.V.V;
            passedType = "ptr";
        }
        else
        {
            passedType = "ptr";
            if (a.V.IsLValue && a.V.Type == pt)
            {
                passed = a.V.V;
            }
            else
            {
                Value cv = ConvertValue(cg, a.V, pt, aloc);
                HoldTemp(cg, cv);
                string slot = ir.Alloca(LlvmType(cg, pt), "tmp");
                ir.Store(LlvmType(cg, pt), cv.V, slot);
                passed = slot;
            }
        }
        if (i > 0)
            callArgs.Append(", ");
        callArgs.Append(passedType + " " + passed);
    }

    // Extra arguments of variadic C functions get the default argument promotions.
    for (var i = fi.ParamTypes.Length; i < args.Length; i += 1)
    {
        Value r = ToRValue(cg, args[i].V);
        SourceLoc aloc = args[i].Source.IsNull() ? loc : args[i].Source.Loc;
        string v = r.V;
        string t = LlvmType(cg, r.Type);
        if (types.IsFloat(r.Type))
        {
            if (types.Bits(r.Type) == 32)
            {
                v = ir.Cast("fpext", "float", v, "double");
                t = "double";
            }
        }
        else if (types.IsBool(r.Type))
        {
            v = ir.Cast("zext", "i1", v, "i32");
            t = "i32";
        }
        else if (types.IsIntegral(r.Type) || types.IsEnum(r.Type))
        {
            if (types.Bits(r.Type) < 32)
            {
                v = ir.Cast(SignedOf(cg, r.Type) ? "sext" : "zext", t, v, "i32");
                t = "i32";
            }
        }
        else if (!(types.IsPointer(r.Type) || types.Kind(r.Type) == TypeKind.Null))
        {
            Fail(cg, aloc, "cannot pass a value of type '" + types.Name(r.Type) + "' to a variadic C function (use '.CStr()' for strings)");
        }
        HoldTemp(cg, r);
        if (callArgs.Length() > 0)
            callArgs.Append(", ");
        callArgs.Append(t + " " + v);
    }

    string retType = LlvmType(cg, fi.Ret);
    string result;
    if (d.IsVariadic)
    {
        var fixedTypes = StringBuilder.Create();
        for (var i = 0; i < fi.ParamTypes.Length; i += 1)
        {
            if (i > 0)
                fixedTypes.Append(", ");
            fixedTypes.Append(fi.ParamRefs[i] != 0 ? "ptr" : LlvmType(cg, fi.ParamTypes[i]));
        }
        result = ir.CallVariadic(retType, fixedTypes.ToString(), fi.LlvmName, callArgs.ToString());
    }
    else
    {
        result = ir.Call(retType, fi.LlvmName, callArgs.ToString());
    }
    if (types.IsVoid(fi.Ret))
        return Rvalue(types.Void, "", false);
    return Rvalue(fi.Ret, result, NeedsArc(cg, fi.Ret));
}

// The dotted name of an expression like A.B.C, or "" if it is anything else.
string DottedName(Compiler cg, Expr e)
{
    if (e.Kind == ExprKind.Name)
        return cg.Tree.GetName(e).Name;
    if (e.Kind == ExprKind.Member)
    {
        var m = cg.Tree.GetMember(e);
        string left = DottedName(cg, m.Object);
        if (left.Length == 0 || m.ViaArrow)
            return "";
        return left + "." + m.Name;
    }
    return "";
}

Value EmitCall(Compiler cg, Expr e)
{
    var call = cg.Tree.GetCall(e);
    var callee = call.Callee;
    int file = cg.Fn[0].File;

    if (callee.Kind == ExprKind.Name)
    {
        var n = cg.Tree.GetName(callee);
        if (!LookupVariable(cg, n.Name).IsNone())
            Fail(cg, e.Loc, "'" + n.Name + "' is a variable, not a function");
        if (n.TypeArgs.Length > 0)
            Fail(cg, e.Loc, "cshc does not support generic functions yet ('" + n.Name + "')");
        int[] cands = LookupFunctions(cg, file, n.Name);
        if (cands.Length == 0)
            Fail(cg, e.Loc, "undefined function '" + n.Name + "'");
        var args = EmitArgs(cg, call.Args);
        int instance = ResolveOverload(cg, cands, args, e.Loc, n.Name);
        return EmitDirectCall(cg, instance, args, e.Loc);
    }

    if (callee.Kind == ExprKind.Member)
    {
        var m = cg.Tree.GetMember(callee);
        string dotted = DottedName(cg, m.Object);
        if (dotted.Length > 0 && !IsLocalName(cg, dotted.Split('.')[0]))
        {
            if (dotted == "Console" || dotted == "Environment")
            {
                var args = EmitArgs(cg, call.Args);
                return EmitBuiltinStatic(cg, dotted, m.Name, args, e.Loc);
            }
            if (IsNamespace(cg, file, dotted))
            {
                int[] cands = LookupFunctions(cg, file, dotted + "." + m.Name);
                if (cands.Length == 0)
                    Fail(cg, e.Loc, "namespace '" + dotted + "' has no function '" + m.Name + "'");
                var args = EmitArgs(cg, call.Args);
                int instance = ResolveOverload(cg, cands, args, e.Loc, m.Name);
                return EmitDirectCall(cg, instance, args, e.Loc);
            }
        }
        Fail(cg, e.Loc, "cshc does not support method calls yet ('" + m.Name + "')");
    }

    Fail(cg, e.Loc, "this expression cannot be called");
    return Value { };
}

// ---------------------------------------------------------------------------
// Builtin static functions
// ---------------------------------------------------------------------------

Value EmitBuiltinStatic(Compiler cg, string type, string method, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    Value none = Rvalue(types.Void, "", false);

    if (type == "Console")
    {
        bool toStderr = method == "WriteError" || method == "WriteErrorLine";
        if (method != "Write" && method != "WriteLine" && !toStderr)
            Fail(cg, loc, "Console has no function '" + method + "'");
        bool newline = method == "WriteLine" || method == "WriteErrorLine";
        if (args.Length > 1)
            Fail(cg, loc, "Console." + method + " takes at most one argument");
        string s;
        if (args.Length == 0)
        {
            if (!newline)
                Fail(cg, loc, "Console.Write needs an argument");
            s = "null";
        }
        else
        {
            Value v = ToRValue(cg, args[0].V);
            if (types.Kind(v.Type) == TypeKind.Null)
            {
                s = v.V;
            }
            else if (types.IsString(v.Type))
            {
                HoldTemp(cg, v);
                s = v.V;
            }
            else
            {
                s = EmitToString(cg, v, args[0].Source.Loc);
                HoldTemp(cg, Rvalue(types.String, s, true)); // EmitToString returns a +1 reference
            }
        }
        ir.Call("void", toStderr ? "@__cs_eprint" : "@__cs_print", "ptr " + s + ", i1 " + (newline ? "true" : "false"));
        return none;
    }

    if (type == "Environment")
    {
        if (method == "Exit")
        {
            if (args.Length != 1)
                Fail(cg, loc, "Environment.Exit takes one argument (exit code)");
            Value code = ConvertValue(cg, args[0].V, types.I32, loc);
            ir.Call("void", "@exit", "i32 " + code.V);
            ir.Unreachable();
            return none;
        }
        if (method == "Panic")
        {
            // Terminates the program like a failed runtime check (exit code 101).
            if (args.Length != 1)
                Fail(cg, loc, "Environment.Panic takes one argument (message)");
            Value msg = ConvertValue(cg, args[0].V, types.String, loc);
            HoldTemp(cg, msg);
            string data = ir.Call("ptr", "@__cs_data", "ptr " + msg.V);
            ir.Call("void", "@__cs_panic", "ptr " + data);
            ir.Unreachable();
            return none;
        }
        Fail(cg, loc, "Environment has no function '" + method + "'");
    }
    Fail(cg, loc, "cshc does not support '" + type + "." + method + "' yet");
    return none;
}
