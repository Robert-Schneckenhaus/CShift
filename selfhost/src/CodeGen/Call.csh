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
int ArgCost(Compiler cg, Arg arg, int paramType, int refKind, bool nullable, bool cstring)
{
    var v = arg.V;
    var types = cg.Types;
    // Parameters that come from C pointers accept null (NULL) and a raw pointer to the same type.
    if (nullable && refKind != 0 && !v.IsRefArg)
    {
        if (types.Kind(v.Type) == TypeKind.Null)
            return 1;
        if (types.IsPointer(v.Type) && types.Elem(v.Type) == paramType)
            return 2;
    }
    // A parameter that C declares as const char* also takes a raw char* (e.g. a string that came from C).
    if (cstring && refKind == 0 && !v.IsRefArg && types.IsPointer(v.Type))
    {
        int pointee = types.Elem(v.Type);
        if (types.IsChar(pointee) || pointee == types.I8 || pointee == types.U8 || types.IsVoid(pointee))
            return 2;
    }
    if (IsInterfaceType(cg, paramType))
        return InterfaceArgCost(cg, v, paramType, refKind);
    switch (refKind)
    {
    case 0:
        if (v.IsRefArg)
            return -1;
        return ConversionCost(cg, v, paramType);
    case 1:
    {
        if (!v.IsRefArg || !v.IsLValue || v.IsConst)
            return -1;
        if (v.Type == paramType)
            return 0;
        var path = new int[0];
        if (types.IsStruct(v.Type) && types.IsStruct(paramType) && StructIsAncestor(cg, paramType, v.Type, ref path))
            return 1;
        return -1;
    }
    default:
    {
        if (v.IsLValue)
        {
            if (v.Type == paramType)
                return 0;
            var path = new int[0];
            if (types.IsStruct(v.Type) && types.IsStruct(paramType) && StructIsAncestor(cg, paramType, v.Type, ref path))
                return 1;
        }
        int c = ConversionCost(cg, v, paramType);
        return c < 0 ? -1 : c + 1;
    }
    }
}

// Chooses the function that matches the arguments best. Candidates are indices in Compiler.Funcs.
int ResolveOverload(Compiler cg, Candidate[] candidates, Arg[] args, int[] explicitTypeArgs, SourceLoc loc, string name)
{
    var best = -1;
    int bestCost = 0;
    bool ambiguous = false;
    string reason = "";

    foreach (var cand in candidates)
    {
        var d = cg.Funcs.Get(cand.Entry).Decl;
        if (args.Length < d.Params.Length || (!d.IsVariadic && args.Length != d.Params.Length))
        {
            reason = "expected " + d.Params.Length.ToString() + " argument(s), got " + args.Length.ToString();
            continue;
        }

        var targs = new int[0];
        if (d.TypeParams.Length > 0)
        {
            if (explicitTypeArgs.Length > 0)
            {
                if (explicitTypeArgs.Length != d.TypeParams.Length)
                {
                    reason = "wrong number of type arguments";
                    continue;
                }
                targs = explicitTypeArgs;
            }
            else if (!InferTypeArgs(cg, cand, args, ref targs))
            {
                reason = "cannot infer the type arguments, specify them explicitly (e.g. " + name + "<int>(...))";
                continue;
            }
        }
        else if (explicitTypeArgs.Length > 0)
        {
            reason = "'" + name + "' is not generic";
            continue;
        }

        var ownerEnv = cand.Owner != 0 ? GetStructInfo(cg, cand.Owner).Env : NoEnv();
        int instance = GetFuncInstance(cg, cand.Entry, cand.Owner, ownerEnv, targs, loc);
        var fi = cg.Instances.Get(instance);

        int total = 0;
        bool ok = true;
        for (var i = 0; i < fi.ParamTypes.Length; i += 1)
        {
            int cost = ArgCost(cg, args[i], fi.ParamTypes[i], fi.ParamRefs[i], d.Params[i].Nullable, d.Params[i].CString);
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

        int score = total * 2 + (d.TypeParams.Length > 0 ? 1 : 0);
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
Value EmitDirectCall(Compiler cg, int instance, string thisPtr, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    UseFunction(cg, instance);
    NoteCall(cg, instance);
    var fi = cg.Instances.Get(instance);
    var d = cg.Funcs.Get(fi.Entry).Decl;
    var interfaceCopies = List<TempRelease>.Create();
    var callArgs = StringBuilder.Create();
    if (fi.HasThis)
        callArgs.Append("ptr " + thisPtr);
    for (var i = 0; i < fi.ParamTypes.Length; i += 1)
    {
        var a = args[i];
        int pt = fi.ParamTypes[i];
        SourceLoc aloc = a.Source.IsNull() ? loc : a.Source.Loc;
        string passed;
        string passedType;
        bool nullable = d.Params[i].Nullable;
        bool cstring = d.Params[i].CString;
        if (IsInterfaceType(cg, pt))
        {
            passed = InterfaceArgument(cg, a.V, pt, fi.ParamRefs[i], interfaceCopies, aloc);
            passedType = "{ ptr, ptr }";
        }
        else if (fi.ParamRefs[i] == 0 && cstring && types.IsPointer(ToRValue(cg, a.V).Type))
        {
            passed = ToRValue(cg, a.V).V; // a raw char* is passed as it is
            passedType = "ptr";
        }
        else if (fi.ParamRefs[i] == 0)
        {
            Value cv = ConvertValue(cg, a.V, pt, aloc);
            HoldTemp(cg, cv);
            passed = cv.V;
            passedType = AbiParam(cg, pt);
            if (d.IsExtern && types.IsFunction(pt))
            {
                // C gets the plain function pointer
                passed = RawFunctionPointer(cg, cv.V);
                passedType = "ptr";
            }
            if (cstring)
            {
                // const char*: pass the character data of the string (null stays NULL). Strings are NUL-terminated.
                string isNull = ir.ICmp("eq", "ptr", cv.V, "null");
                passed = ir.Select(isNull, "ptr", "null", ir.ByteGep(cv.V, "16"));
                passedType = "ptr";
            }
        }
        else if (nullable && !a.V.IsRefArg && types.Kind(a.V.Type) == TypeKind.Null)
        {
            passed = "null";
            passedType = "ptr";
        }
        else if (nullable && !a.V.IsRefArg && types.IsPointer(a.V.Type) && types.Elem(a.V.Type) == pt)
        {
            passed = ToRValue(cg, a.V).V;
            passedType = "ptr";
        }
        else if (fi.ParamRefs[i] == 1)
        {
            passed = a.V.V;
            passedType = "ptr";
        }
        else
        {
            passedType = "ptr";
            var ancestorPath = new int[0];
            if (a.V.IsLValue && (a.V.Type == pt || (types.IsStruct(a.V.Type) && types.IsStruct(pt) && StructIsAncestor(cg, pt, a.V.Type, ref ancestorPath))))
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
        if (callArgs.Length() > 0)
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

    // Shims return structs through an extra trailing pointer parameter and themselves return void.
    string outSlot = "";
    if (d.RetOut)
    {
        outSlot = ir.Alloca(LlvmType(cg, fi.Ret), "ret");
        if (callArgs.Length() > 0)
            callArgs.Append(", ");
        callArgs.Append("ptr " + outSlot);
    }

    bool rawFunctionResult = d.IsExtern && types.IsFunction(fi.Ret);
    string retType = d.RetOut ? "void" : (rawFunctionResult ? "ptr" : AbiReturn(cg, fi.Ret));
    string result;
    if (d.IsVariadic)
    {
        var fixedTypes = StringBuilder.Create();
        for (var i = 0; i < fi.ParamTypes.Length; i += 1)
        {
            if (i > 0)
                fixedTypes.Append(", ");
            fixedTypes.Append(fi.ParamRefs[i] != 0 ? "ptr" : ExternAbiParam(cg, fi.ParamTypes[i]));
        }
        result = ir.CallVariadic(retType, fixedTypes.ToString(), fi.LlvmName, callArgs.ToString());
    }
    else
    {
        result = ir.Call(retType, fi.LlvmName, callArgs.ToString());
    }
    ReleaseInterfaceCopies(cg, interfaceCopies);
    if (d.RetOut)
        return Rvalue(fi.Ret, ir.Load(LlvmType(cg, fi.Ret), outSlot), NeedsArc(cg, fi.Ret));
    if (types.IsVoid(fi.Ret))
        return Rvalue(types.Void, "", false);
    if (d.RetCString)
    {
        // const char* result: copy it into a string that the caller owns.
        return Rvalue(types.String, ir.Call("ptr", "@__cs_from_cstr", "ptr " + result), true);
    }
    if (rawFunctionResult)
        return Rvalue(fi.Ret, ir.InsertValue("{ ptr, ptr }", "zeroinitializer", "ptr", result, "0"), false);
    return Rvalue(fi.Ret, result, NeedsArc(cg, fi.Ret));
}

// How the C ABI passes small integers: they are extended to 32 bits by the caller.
string AbiExtension(Compiler cg, int t)
{
    var types = cg.Types;
    if (types.IsBool(t))
        return "zeroext";
    if ((types.IsIntegral(t) || types.IsEnum(t)) && types.Bits(t) < 32)
        return (types.IsInt(t) && types.IsSigned(t)) ? "signext" : "zeroext";
    return "";
}

// "i8 zeroext" for a parameter of the type.
string AbiParam(Compiler cg, int t)
{
    string ext = AbiExtension(cg, t);
    return ext.Length > 0 ? LlvmType(cg, t) + " " + ext : LlvmType(cg, t);
}

// A parameter of a C function: function values are plain function pointers there.
string ExternAbiParam(Compiler cg, int t)
{
    return cg.Types.IsFunction(t) ? "ptr" : AbiParam(cg, t);
}

// "zeroext i8" for a result of the type.
string AbiReturn(Compiler cg, int t)
{
    string ext = AbiExtension(cg, t);
    return ext.Length > 0 ? ext + " " + LlvmType(cg, t) : LlvmType(cg, t);
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

// The free functions a name can refer to, as candidates.
Candidate[] FreeCandidates(Compiler cg, int file, string name)
{
    var list = List<Candidate>.Create();
    foreach (var f in LookupFunctions(cg, file, name))
        list.Add(Candidate { Entry = f, Owner = 0 });
    return list.ToArray();
}

// A call of a free function or of a method of the current struct by its simple name.
// 'viaStart': the call is the operand of 'start' (see EmitStart). A 'thread' function can only be called that way, and
// 'start' only works with a direct call to one.
Value EmitNameCall(Compiler cg, Expr e, CallExpr call, NameExpr n, bool viaStart)
{
    Value variable = LookupVariable(cg, n.Name);
    if (!variable.IsNone())
    {
        if (!IsCallableType(cg, variable.Type))
            Fail(cg, e.Loc, "'" + n.Name + "' is a variable, not a function");
        RejectIndirectStart(cg, viaStart, e.Loc);
        return EmitIndirectCall(cg, variable, EmitArgs(cg, call.Args), e.Loc);
    }
    int currentOwner = CurrentOwner(cg);
    if (currentOwner != 0)
    {
        // A field with a function type is called like a function.
        var fieldPath = FindField(cg, currentOwner, n.Name);
        if (fieldPath.Found && IsCallableType(cg, fieldPath.Type))
        {
            RejectIndirectStart(cg, viaStart, e.Loc);
            Value field = FieldAccess(cg, ThisValue(cg, e.Loc), n.Name, e.Loc);
            return EmitIndirectCall(cg, field, EmitArgs(cg, call.Args), e.Loc);
        }
    }
    int globalIndex = LookupGlobal(cg, cg.Fn[0].File, n.Name);
    if (globalIndex >= 0 && (CurrentOwner(cg) == 0 || MethodCandidates(cg, CurrentOwner(cg), n.Name).Length == 0))
    {
        Value global = GlobalUse(cg, globalIndex);
        if (IsCallableType(cg, global.Type))
        {
            RejectIndirectStart(cg, viaStart, e.Loc);
            return EmitIndirectCall(cg, global, EmitArgs(cg, call.Args), e.Loc);
        }
    }

    var cands = new Candidate[0];
    int owner = CurrentOwner(cg);
    if (owner != 0)
        cands = MethodCandidates(cg, owner, n.Name);
    if (cands.Length == 0)
        cands = FreeCandidates(cg, cg.Fn[0].File, n.Name);
    if (cands.Length == 0 && IsEmbedName(n.Name))
    {
        RejectIndirectStart(cg, viaStart, e.Loc);
        return EmitEmbed(cg, e, call, n.Name);
    }
    if (cands.Length == 0)
        Fail(cg, e.Loc, "undefined function '" + n.Name + "'");

    var args = EmitArgs(cg, call.Args);
    int instance = ResolveOverload(cg, cands, args, ResolveTypeArgs(cg, n.TypeArgs), e.Loc, n.Name);
    if (IsThreadInstance(cg, instance))
    {
        if (!viaStart)
            Fail(cg, e.Loc, "call to the 'thread' function '" + n.Name + "' must be prefixed with 'start': 'start " + n.Name +
                                "(...)'");
        return EmitThreadSpawn(cg, instance, args, e.Loc);
    }
    if (viaStart)
        Fail(cg, e.Loc, "'start' can only be used with a 'thread' function, not '" + n.Name + "'");
    string thisPtr = "";
    if (cg.Instances.Get(instance).HasThis)
    {
        if (cg.Fn[0].ThisSlot == null || cg.Fn[0].ThisSlot.Length == 0)
            Fail(cg, e.Loc, "cannot call the instance method '" + n.Name + "' from a static context");
        thisPtr = cg.Ir.Load("ptr", cg.Fn[0].ThisSlot);
    }
    return EmitDirectCall(cg, instance, thisPtr, args, e.Loc);
}

// obj.Method(args), Type.Method(args), Namespace.Function(args), Console.WriteLine(...)
Value EmitMemberCall(Compiler cg, Expr e, CallExpr call, MemberExpr m, bool viaStart)
{
    var types = cg.Types;
    int file = cg.Fn[0].File;
    var methodTypeArgs = ResolveTypeArgs(cg, m.TypeArgs);
    string dotted = DottedName(cg, m.Object);
    bool colorColor = dotted.Length > 0 && ColorColorMeansType(cg, dotted, m.Name, e.Loc);
    if (dotted.Length > 0 && (colorColor || (!IsLocalName(cg, dotted.Split('.')[0]) &&
        (CurrentOwner(cg) == 0 || !FindField(cg, CurrentOwner(cg), dotted.Split('.')[0]).Found))))
    {
        if (dotted == "Console" || dotted == "Environment" || dotted == "Memory")
        {
            RejectIndirectStart(cg, viaStart, e.Loc);
            var builtinArgs = EmitArgs(cg, call.Args);
            return EmitBuiltinStatic(cg, dotted, m.Name, builtinArgs, e.Loc);
        }
        var entry = TypeDeclEntry { };
        if (dotted == "Array")
        {
            RejectIndirectStart(cg, viaStart, e.Loc);
            if (m.Name != "Copy")
                Fail(cg, e.Loc, "Array has no function '" + m.Name + "'");
            return EmitArrayCopy(cg, EmitArgs(cg, call.Args), e.Loc);
        }
        if (dotted == "string")
        {
            RejectIndirectStart(cg, viaStart, e.Loc);
            var stringArgs = EmitArgs(cg, call.Args);
            if (m.Name == "FromCStr")
                return EmitStringFromCStr(cg, stringArgs, e.Loc);
            if (m.Name == "FromBytes")
                return EmitStringFromBytes(cg, stringArgs, e.Loc);
            var foundStatic = false;
            Value sr = EmitExtensionCall(cg, "String", false, Value { }, m.Name, stringArgs, e.Loc, ref foundStatic);
            if (foundStatic)
                return sr;
            Fail(cg, e.Loc, "type 'string' has no static method '" + m.Name + "'");
        }
        if (dotted == "SharedPtr" && !LookupTypeDecl(cg, file, dotted, ref entry))
        {
            RejectIndirectStart(cg, viaStart, e.Loc);
            var spArgs = ResolveTypeArgs(cg, LastTypeArgs(cg, m.Object));
            if (spArgs.Length != 1)
                Fail(cg, e.Loc, "'SharedPtr' expects exactly one type argument");
            int sp = types.SharedPtrOf(spArgs[0]);
            if (m.Name != "Create")
                Fail(cg, e.Loc, "type '" + types.Name(sp) + "' has no static method '" + m.Name + "'");
            var createArgs = EmitArgs(cg, call.Args);
            if (createArgs.Length != 1)
                Fail(cg, e.Loc, "SharedPtr<T>.Create takes one argument (the value)");
            return EmitSharedPtrCreate(cg, sp, createArgs[0].V, e.Loc);
        }
        if (PrimitiveType(cg, dotted) != 0)
            Fail(cg, e.Loc, "cshc does not support '" + dotted + "." + m.Name + "' yet");
        if (LookupTypeDecl(cg, file, dotted, ref entry))
        {
            if (entry.Kind != DeclKind.Struct)
                Fail(cg, e.Loc, "cshc does not support enums and interfaces yet ('" + dotted + "')");
            // Type.Method(...): a static method
            int st = GetStructType(cg, entry.Index, ResolveTypeArgs(cg, LastTypeArgs(cg, m.Object)), e.Loc);
            var scands = MethodCandidates(cg, st, m.Name);
            if (scands.Length == 0)
                Fail(cg, e.Loc, "struct '" + types.Name(st) + "' has no method '" + m.Name + "'");
            var sargs = EmitArgs(cg, call.Args);
            int sinstance = ResolveOverload(cg, scands, sargs, methodTypeArgs, e.Loc, m.Name);
            var sfi = cg.Instances.Get(sinstance);
            if (sfi.HasThis)
                Fail(cg, e.Loc, "'" + types.Name(st) + "." + m.Name + "' is an instance method and needs an object");
            if (m.Name.Length > 0 && m.Name[0] == '_' && CurrentOwner(cg) != sfi.Owner)
                Fail(cg, e.Loc, "method '" + m.Name + "' is private to '" + types.Name(sfi.Owner) + "'");
            if (IsThreadInstance(cg, sinstance))
            {
                if (!viaStart)
                    Fail(cg, e.Loc, "call to the 'thread' method '" + types.Name(st) + "." + m.Name + "' must be prefixed with 'start'");
                return EmitThreadSpawn(cg, sinstance, sargs, e.Loc);
            }
            if (viaStart)
                Fail(cg, e.Loc, "'start' can only be used with a 'thread' function, not '" + types.Name(st) + "." + m.Name + "'");
            return EmitDirectCall(cg, sinstance, "", sargs, e.Loc);
        }
        if (IsNamespace(cg, file, dotted))
        {
            var ncands = FreeCandidates(cg, file, dotted + "." + m.Name);
            if (ncands.Length == 0)
                Fail(cg, e.Loc, "namespace '" + dotted + "' has no function '" + m.Name + "'");
            var nargs = EmitArgs(cg, call.Args);
            int ninstance = ResolveOverload(cg, ncands, nargs, methodTypeArgs, e.Loc, m.Name);
            if (IsThreadInstance(cg, ninstance))
            {
                if (!viaStart)
                    Fail(cg, e.Loc, "call to the 'thread' function '" + dotted + "." + m.Name + "' must be prefixed with 'start'");
                return EmitThreadSpawn(cg, ninstance, nargs, e.Loc);
            }
            if (viaStart)
                Fail(cg, e.Loc, "'start' can only be used with a 'thread' function, not '" + dotted + "." + m.Name + "'");
            return EmitDirectCall(cg, ninstance, "", nargs, e.Loc);
        }
    }

    // An instance call: never a 'thread' function (a thread function cannot be an instance method).
    RejectIndirectStart(cg, viaStart, e.Loc);
    Value obj = EmitExpr(cg, m.Object);
    if (m.ViaArrow)
        obj = DerefPointer(cg, obj, e.Loc);
    else if (types.IsPointer(obj.Type))
        Fail(cg, e.Loc, "use '->' to call methods through a pointer");
    if (types.IsStruct(obj.Type) && MethodCandidates(cg, obj.Type, m.Name).Length == 0)
    {
        // A field with a function type is called like a method: obj.Callback(x)
        var fieldPath = FindField(cg, obj.Type, m.Name);
        if (fieldPath.Found && IsCallableType(cg, fieldPath.Type))
        {
            Value field = FieldAccess(cg, obj, m.Name, e.Loc);
            return EmitIndirectCall(cg, field, EmitArgs(cg, call.Args), e.Loc);
        }
    }
    var args = EmitArgs(cg, call.Args);
    if (IsCallableType(cg, obj.Type) && m.Name == "Invoke")
        return EmitIndirectCall(cg, obj, args, e.Loc);
    if (types.Kind(obj.Type) == TypeKind.Interface)
        return EmitInterfaceCall(cg, obj, m.Name, args, e.Loc);
    if (!types.IsStruct(obj.Type))
        return EmitBuiltinMethod(cg, obj, m.Name, args, e.Loc);
    return EmitMethodCallOn(cg, obj, m.Name, args, methodTypeArgs, e.Loc);
}

// obj.Name(args) for a struct value: resolves the instance method and calls it on the object (in place if it is a
// variable, else on a temporary copy). Also used by the indexer (obj[i] is obj.Get(i), obj[i] = v is obj.Set(i, v)).
Value EmitMethodCallOn(Compiler cg, Value obj, string name, Arg[] args, int[] methodTypeArgs, SourceLoc loc)
{
    var types = cg.Types;
    var cands = MethodCandidates(cg, obj.Type, name);
    if (cands.Length == 0)
        Fail(cg, loc, "struct '" + types.Name(obj.Type) + "' has no method '" + name + "'");
    int instance = ResolveOverload(cg, cands, args, methodTypeArgs, loc, name);
    var fi = cg.Instances.Get(instance);
    if (!fi.HasThis)
        Fail(cg, loc, "'" + name + "' is a static method, call it as '" + types.Name(fi.Owner) + "." + name + "(...)'");
    if (name.Length > 0 && name[0] == '_' && CurrentOwner(cg) != fi.Owner)
        Fail(cg, loc, "method '" + name + "' is private to '" + types.Name(fi.Owner) + "'");

    string thisPtr;
    if (obj.IsLValue && !obj.IsConst)
    {
        thisPtr = obj.V;
    }
    else if (obj.IsLValue)
    {
        // A read-only alias ('const ref'): the method could modify the object, so it works on a copy.
        Value copy = Rvalue(obj.Type, Consume(cg, obj), true);
        HoldTemp(cg, copy);
        thisPtr = cg.Ir.Alloca(LlvmType(cg, obj.Type), "tmp");
        cg.Ir.Store(LlvmType(cg, obj.Type), copy.V, thisPtr);
    }
    else
    {
        HoldTemp(cg, obj);
        thisPtr = cg.Ir.Alloca(LlvmType(cg, obj.Type), "tmp");
        cg.Ir.Store(LlvmType(cg, obj.Type), obj.V, thisPtr);
    }
    return EmitDirectCall(cg, instance, thisPtr, args, loc);
}

Value EmitCall(Compiler cg, Expr e)
{
    return EmitCallVia(cg, e, false);
}

// 'start f(...)': the only way to call a 'thread' function.
Value EmitStart(Compiler cg, Expr e)
{
    var s = cg.Tree.GetStart(e);
    if (s.Operand.Kind != ExprKind.Call)
        Fail(cg, e.Loc, "'start' must be followed directly by a call, e.g. 'start Foo(...)'");
    return EmitCallVia(cg, s.Operand, true);
}

void RejectIndirectStart(Compiler cg, bool viaStart, SourceLoc loc)
{
    if (viaStart)
        Fail(cg, loc, "'start' can only be used with a direct call to a 'thread' function");
}

bool IsThreadInstance(Compiler cg, int instance)
{
    return cg.Funcs.Get(cg.Instances.Get(instance).Entry).Decl.IsThread;
}

Value EmitCallVia(Compiler cg, Expr e, bool viaStart)
{
    var call = cg.Tree.GetCall(e);
    var callee = call.Callee;
    if (callee.Kind == ExprKind.Name)
        return EmitNameCall(cg, e, call, cg.Tree.GetName(callee), viaStart);
    if (callee.Kind == ExprKind.Member)
        return EmitMemberCall(cg, e, call, cg.Tree.GetMember(callee), viaStart);
    // Any other expression that yields a function: handlers[i](x), MakeCallback()(x)
    RejectIndirectStart(cg, viaStart, e.Loc);
    Value fv = EmitExpr(cg, callee);
    if (!IsCallableType(cg, fv.Type))
        Fail(cg, e.Loc, "this expression cannot be called (type '" + cg.Types.Name(fv.Type) + "')");
    return EmitIndirectCall(cg, fv, EmitArgs(cg, call.Args), e.Loc);
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

    if (type == "Memory" && method == "CopyForThread")
    {
        // A copy that shares no reference count with the original: new blocks for its strings (Mutex<T>, threads).
        if (args.Length != 1)
            Fail(cg, loc, "Memory.CopyForThread takes one argument");
        Value original = ToRValue(cg, args[0].V);
        if (!IsThreadTransferable(cg, original.Type))
            Fail(cg, loc, "'" + types.Name(original.Type) + "' cannot be copied for another thread (only values, strings, SharedPtr<T> of " +
                              "thread-safe values, and Optional<T>/Error<T>/structs of them)");
        HoldTemp(cg, original);
        return Rvalue(original.Type, ThreadCopy(cg, original.Type, original.V), NeedsArc(cg, original.Type));
    }
    if (type == "Memory")
    {
        RequireUnsafe(cg, loc, "Memory." + method);
        if (method == "Allocate")
        {
            if (args.Length != 1)
                Fail(cg, loc, "Memory.Allocate takes one argument (size in bytes)");
            Value n = ToRValue(cg, args[0].V);
            if (!types.IsIntegral(n.Type))
                Fail(cg, loc, "Memory.Allocate needs an integer size");
            bool sizeSigned = types.IsInt(n.Type) && types.IsSigned(n.Type);
            string size = NumericConvert(cg, n.V, n.Type, sizeSigned ? types.I64 : types.U64);
            ir.Declare("@malloc", "declare ptr @malloc(i64)");
            return Rvalue(types.PointerTo(types.Void), ir.Call("ptr", "@malloc", "i64 " + size), false);
        }
        if (method == "Free")
        {
            if (args.Length != 1)
                Fail(cg, loc, "Memory.Free takes one argument");
            Value p = ToRValue(cg, args[0].V);
            if (!types.IsPointer(p.Type) && types.Kind(p.Type) != TypeKind.Null)
                Fail(cg, loc, "Memory.Free needs a pointer");
            ir.Call("void", "@free", "ptr " + p.V);
            return none;
        }
        Fail(cg, loc, "Memory has no function '" + method + "'");
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

// Calls a function of the standard library that extends a built-in type: "String.Method(self, args...)".
Value EmitExtensionCall(Compiler cg, string ns, bool hasSelf, Value self, string method, Arg[] args, SourceLoc loc, ref bool found)
{
    var cands = FreeCandidates(cg, cg.Fn[0].File, ns + "." + method);
    found = cands.Length > 0;
    if (!found)
        return Value { };
    var all = List<Arg>.Create();
    if (hasSelf)
        all.Add(Arg { V = self });
    foreach (var a in args)
        all.Add(a);
    var list = all.ToArray();
    int instance = ResolveOverload(cg, cands, list, new int[0], loc, ns + "." + method);
    return EmitDirectCall(cg, instance, "", list, loc);
}

// ---------------------------------------------------------------------------
// Builtin methods of strings, numbers, bool and char
// ---------------------------------------------------------------------------

void ExpectArgs(Compiler cg, Arg[] args, int n, string type, string method, SourceLoc loc)
{
    if (args.Length != n)
        Fail(cg, loc, "'" + type + "." + method + "' takes " + n.ToString() + " argument(s)");
}

// SharedPtr<T>.Create(value): moves the value into a new block {i64 count = 1, i64 unused, T value}.
Value EmitSharedPtrCreate(Compiler cg, int sp, Value value, SourceLoc loc)
{
    int elem = cg.Types.Elem(sp);
    Value v = ConvertValue(cg, value, elem, loc);
    string owned = Consume(cg, v);
    string block = cg.Ir.Call("ptr", "@__cs_alloc", "i64 " + SizeOfType(cg, elem) + ", i64 0");
    cg.Ir.Store(LlvmType(cg, elem), owned, DataPtr(cg, block));
    return Rvalue(sp, block, true);
}

Value EmitBuiltinMethod(Compiler cg, Value obj, string method, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    int t = obj.Type;
    string tname = types.Name(t);

    if (types.IsSharedPtr(t))
    {
        Value p = ToRValue(cg, obj);
        HoldTemp(cg, p);
        int elem = types.Elem(t);
        if (method == "IsNull")
        {
            ExpectArgs(cg, args, 0, tname, method, loc);
            return MakeBool(cg, ir.ICmp("eq", "ptr", p.V, "null"));
        }
        if (method == "Get")
        {
            // A copy of the shared value (retained if it needs ARC itself).
            ExpectArgs(cg, args, 0, tname, method, loc);
            EmitPanicIf(cg, ir.ICmp("eq", "ptr", p.V, "null"), "SharedPtr.Get(): the pointer is null");
            string value = ir.Load(LlvmType(cg, elem), DataPtr(cg, p.V));
            EmitRetain(cg, elem, value);
            return Rvalue(elem, value, true);
        }
        if (method == "Ptr")
        {
            // A raw pointer to the shared value for in-place access; only the reference count is thread-safe.
            ExpectArgs(cg, args, 0, tname, method, loc);
            RequireUnsafe(cg, loc, "SharedPtr.Ptr()");
            EmitPanicIf(cg, ir.ICmp("eq", "ptr", p.V, "null"), "SharedPtr.Ptr(): the pointer is null");
            return Rvalue(types.PointerTo(elem), DataPtr(cg, p.V), false);
        }
        Fail(cg, loc, "type '" + tname + "' has no method '" + method + "'");
    }

    if (types.IsString(t))
    {
        Value s = ToRValue(cg, obj);
        if (method == "ToString")
        {
            ExpectArgs(cg, args, 0, tname, method, loc);
            return s;
        }
        if (method == "Clone")
        {
            // Strings are immutable, but an explicit independent copy is possible.
            ExpectArgs(cg, args, 0, tname, method, loc);
            HoldTemp(cg, s);
            string len = ir.Cast("trunc", "i64", ir.Call("i64", "@__cs_len", "ptr " + s.V), "i32");
            return Rvalue(types.String, ir.Call("ptr", "@__cs_substring", "ptr " + s.V + ", i32 0, i32 " + len), true);
        }
        if (method == "CStr")
        {
            ExpectArgs(cg, args, 0, tname, method, loc);
            RequireUnsafe(cg, loc, "string.CStr()");
            HoldTemp(cg, s);
            return Rvalue(types.PointerTo(types.Char), ir.Call("ptr", "@__cs_data", "ptr " + s.V), false);
        }
        if (method == "Substring")
        {
            if (args.Length == 0 || args.Length > 2)
                Fail(cg, loc, "string.Substring takes (start) or (start, length)");
            HoldTemp(cg, s);
            string start = ConvertValue(cg, args[0].V, types.I32, loc).V;
            string count;
            if (args.Length == 2)
                count = ConvertValue(cg, args[1].V, types.I32, loc).V;
            else
                count = ir.Bin("sub", "i32", ir.Cast("trunc", "i64", ir.Call("i64", "@__cs_len", "ptr " + s.V), "i32"), start);
            return Rvalue(types.String, ir.Call("ptr", "@__cs_substring", "ptr " + s.V + ", i32 " + start + ", i32 " + count), true);
        }
        // Everything else (Contains, Trim, Split, ...) is written in CShift: namespace String of the standard library.
        var found = false;
        Value r = EmitExtensionCall(cg, "String", true, s, method, args, loc, ref found);
        if (found)
            return r;
        if (!cg.St[0].StdlibLoaded)
            Fail(cg, loc, "cshc does not support the string method '" + method + "' yet (the standard library is not loaded)");
        Fail(cg, loc, "type 'string' has no method '" + method + "'");
    }
    else if (types.IsArray(t))
    {
        if (method == "Clone")
        {
            ExpectArgs(cg, args, 0, tname, method, loc);
            return EmitArrayClone(cg, obj);
        }
    }
    else if (types.IsNumeric(t) || types.IsBool(t) || types.IsEnum(t))
    {
        if (method == "ToString")
        {
            ExpectArgs(cg, args, 0, tname, method, loc);
            return Rvalue(types.String, EmitToString(cg, obj, loc), true);
        }
        if (method == "Equals")
        {
            ExpectArgs(cg, args, 1, tname, method, loc);
            Value a = ToRValue(cg, obj);
            Value b = ConvertValue(cg, args[0].V, t, loc);
            return EmitCompare(cg, BinOp.Eq, a, b, loc);
        }
        if (method == "CompareTo" && types.IsNumeric(t))
        {
            ExpectArgs(cg, args, 1, tname, method, loc);
            Value a = ToRValue(cg, obj);
            Value b = ConvertValue(cg, args[0].V, t, loc);
            string ty = LlvmType(cg, t);
            string gt;
            string lt;
            if (types.IsFloat(t))
            {
                gt = ir.FCmp("ogt", ty, a.V, b.V);
                lt = ir.FCmp("olt", ty, a.V, b.V);
            }
            else if (types.IsInt(t) && types.IsSigned(t))
            {
                gt = ir.ICmp("sgt", ty, a.V, b.V);
                lt = ir.ICmp("slt", ty, a.V, b.V);
            }
            else
            {
                gt = ir.ICmp("ugt", ty, a.V, b.V);
                lt = ir.ICmp("ult", ty, a.V, b.V);
            }
            string r = ir.Bin("sub", "i32", ir.Cast("zext", "i1", gt, "i32"), ir.Cast("zext", "i1", lt, "i32"));
            return Rvalue(types.I32, r, false);
        }
        if (method == "GetHashCode")
        {
            ExpectArgs(cg, args, 0, tname, method, loc);
            Value a = ToRValue(cg, obj);
            string v = a.V;
            int bits = types.Bits(t);
            if (types.IsFloat(t))
                v = ir.Cast("bitcast", LlvmType(cg, t), v, "i" + bits.ToString());
            bool isSigned = (types.IsInt(t) || types.IsEnum(t)) && types.IsSigned(t);
            if (bits < 32)
                v = ir.Cast(isSigned ? "sext" : "zext", "i" + bits.ToString(), v, "i32");
            else if (bits == 64)
            {
                string low = ir.Cast("trunc", "i64", v, "i32");
                string high = ir.Cast("trunc", "i64", ir.Bin("lshr", "i64", v, "32"), "i32");
                v = ir.Bin("xor", "i32", low, high);
            }
            return Rvalue(types.I32, v, false);
        }
    }
    Fail(cg, loc, "type '" + tname + "' has no method '" + method + "'");
    return obj;
}
