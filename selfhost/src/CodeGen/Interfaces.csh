// Interfaces as parameter types (only in the self-hosted compiler): dynamic dispatch without an allocation.
//
//     interface IShape { double Area(); void Grow(double f); }
//
//     double Report(const ref IShape shape)          // any struct that implements IShape
//     {
//         return shape.Area();                        // called through the method table
//     }
//
//     Report(circle);           // const ref: the callee works on a copy on the caller's stack
//     Enlarge(ref circle);      // ref: the callee works on 'circle' itself
//
// An interface can only be the type of a 'ref' or 'const ref' parameter (and a generic constraint). The parameter is
// { ptr data, ptr table }: a pointer to the struct and the method table of that struct for the interface - a
// constant [method 1, method 2, ...] in the order of the interface's methods (struct methods take 'this' as their
// first parameter, so the table holds them directly). Nothing is allocated, and since such a parameter cannot be
// stored anywhere (no interface variables, fields, results or captures), it cannot outlive the struct it points to.
// For 'const ref' the caller passes a copy (on its stack, released after the call), so the methods cannot change the
// caller's value; for 'ref' it passes its own variable.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

struct InterfaceMethodSig
{
    string Name;
    int[] ParamTypes;
    int[] ParamRefs;
    int Ret;
}

// The signature of method k of the interface, with the interface's type arguments.
InterfaceMethodSig InterfaceMethod(Compiler cg, int iface, int k)
{
    var ii = cg.InterfaceInfos.Get(cg.Types.Decl(iface));
    var ie = cg.Interfaces.Get(ii.Entry);
    var m = ie.Decl.Methods[k];
    var sig = InterfaceMethodSig { Name = m.Name };
    sig.ParamTypes = new int[m.Params.Length];
    sig.ParamRefs = new int[m.Params.Length];
    for (var i = 0; i < m.Params.Length; i += 1)
    {
        sig.ParamTypes[i] = ResolveParamType(cg, m.Params[i], ie.File, ii.Env);
        sig.ParamRefs[i] = (int)m.Params[i].Ref;
    }
    sig.Ret = ResolveValueType(cg, m.Ret.Id, ie.File, ii.Env);
    return sig;
}

int InterfaceMethodCount(Compiler cg, int iface)
{
    var ii = cg.InterfaceInfos.Get(cg.Types.Decl(iface));
    return cg.Interfaces.Get(ii.Entry).Decl.Methods.Length;
}

// The method of the struct that implements method k of the interface (a function instance), or -1.
int FindImplementation(Compiler cg, int structType, int iface, int k)
{
    var sig = InterfaceMethod(cg, iface, k);
    foreach (var c in MethodCandidates(cg, structType, sig.Name))
    {
        var cd = cg.Funcs.Get(c.Entry).Decl;
        if (cd.TypeParams.Length > 0 || cd.IsStatic)
            continue;
        int instance = GetFuncInstance(cg, c.Entry, c.Owner, GetStructInfo(cg, c.Owner).Env, new int[0], cd.Loc);
        var fi = cg.Instances.Get(instance);
        if (fi.Ret != sig.Ret || fi.ParamTypes.Length != sig.ParamTypes.Length)
            continue;
        bool same = true;
        for (var i = 0; i < sig.ParamTypes.Length; i += 1)
            if (fi.ParamTypes[i] != sig.ParamTypes[i] || fi.ParamRefs[i] != sig.ParamRefs[i])
                same = false;
        if (same)
            return instance;
    }
    return -1;
}

// The method table of the struct for the interface (a constant, written the first time it is needed).
string InterfaceTable(Compiler cg, int structType, int iface)
{
    var types = cg.Types;
    string name = "@\"vtable." + types.Name(structType) + "." + types.Name(iface) + "\"";
    if (!cg.Ir.Declared.Add(name))
        return name;
    int count = InterfaceMethodCount(cg, iface);
    var entries = StringBuilder.Create();
    for (var k = 0; k < count; k += 1)
    {
        int instance = FindImplementation(cg, structType, iface, k);
        if (instance < 0)
            Fail(cg, SourceLoc { }, "internal error: '" + types.Name(structType) + "' does not implement '" + InterfaceMethod(cg, iface, k).Name + "'");
        UseFunction(cg, instance);
        NoteCall(cg, instance); // may be called through the table
        entries.Append((k > 0 ? ", " : "") + "ptr " + cg.Instances.Get(instance).LlvmName);
    }
    cg.Ir.Globals.Append(name + " = internal constant [" + count.ToString() + " x ptr] [" + entries.ToString() + "]\n");
    return name;
}

bool IsInterfaceType(Compiler cg, int t)
{
    return cg.Types.Kind(t) == TypeKind.Interface;
}

// The cost of passing the argument to a 'ref' (refKind 1) or 'const ref' (2) parameter of interface type, -1 if not.
int InterfaceArgCost(Compiler cg, Value v, int iface, int refKind)
{
    var types = cg.Types;
    if (refKind == 0)
        return -1;
    if (refKind == 1 && (!v.IsRefArg || !v.IsLValue || v.IsConst))
        return -1;
    if (refKind == 2 && v.IsRefArg)
        return -1;
    if (v.Type == iface)
        return 0;
    if (types.IsStruct(v.Type) && StructImplements(cg, v.Type, iface))
        return 1;
    if (IsUnionType(cg, v.Type) && UnionImplements(cg, v.Type, iface))
        return 1;
    return -1;
}

// The { data, table } value for an interface parameter. For 'const ref' a struct is copied into a slot of the caller;
// 'releaseSlots' collects those slots, to be released after the call.
string InterfaceArgument(Compiler cg, Value v, int iface, int refKind, List<TempRelease> releaseSlots, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    if (v.Type == iface)
        return ToRValue(cg, v).V; // an interface parameter passed on
    if (IsUnionType(cg, v.Type))
    {
        // the member the union holds: in place for 'ref', in a copy of the union for 'const ref'
        string unionSlot = v.V;
        if (refKind != 1)
        {
            string uty = LlvmType(cg, v.Type);
            unionSlot = ir.Alloca(uty, "iface.copy");
            ir.Store(uty, Consume(cg, ToRValue(cg, v)), unionSlot);
            if (NeedsArc(cg, v.Type))
                releaseSlots.Add(TempRelease { Type = v.Type, Value = unionSlot });
        }
        return UnionAsInterface(cg, v.Type, unionSlot, iface);
    }
    if (!types.IsStruct(v.Type) || !StructImplements(cg, v.Type, iface))
        Fail(cg, loc, "'" + types.Name(v.Type) + "' does not implement '" + types.Name(iface) + "'");
    string data;
    if (refKind == 1)
        data = v.V;
    else
    {
        string ty = LlvmType(cg, v.Type);
        data = ir.Alloca(ty, "iface.copy");
        ir.Store(ty, Consume(cg, ToRValue(cg, v)), data);
        if (NeedsArc(cg, v.Type))
            releaseSlots.Add(TempRelease { Type = v.Type, Value = data });
    }
    string agg = ir.InsertValue("{ ptr, ptr }", "undef", "ptr", data, "0");
    return ir.InsertValue("{ ptr, ptr }", agg, "ptr", InterfaceTable(cg, v.Type, iface), "1");
}

// After a call: releases the copies made for 'const ref' interface parameters (loaded from their slots, because the
// methods may have changed them).
void ReleaseInterfaceCopies(Compiler cg, List<TempRelease> slots)
{
    foreach (var s in slots)
        EmitRelease(cg, s.Type, cg.Ir.Load(LlvmType(cg, s.Type), s.Value));
}

// shape.Method(args) on an interface parameter: the method from the table, called with the data pointer as 'this'.
Value EmitInterfaceCall(Compiler cg, Value obj, string name, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    int iface = obj.Type;
    int count = InterfaceMethodCount(cg, iface);
    int chosen = -1;
    int bestCost = 1000000;
    for (var k = 0; k < count; k += 1)
    {
        var sig = InterfaceMethod(cg, iface, k);
        if (sig.Name != name || sig.ParamTypes.Length != args.Length)
            continue;
        int total = 0;
        for (var i = 0; i < args.Length && total >= 0; i += 1)
        {
            int c = IsInterfaceType(cg, sig.ParamTypes[i]) ? InterfaceArgCost(cg, args[i].V, sig.ParamTypes[i], sig.ParamRefs[i])
                  : sig.ParamRefs[i] != 0 ? (args[i].V.Type == sig.ParamTypes[i] ? 0 : -1) : ConversionCost(cg, args[i].V, sig.ParamTypes[i]);
            total = c < 0 ? -1 : total + c;
        }
        if (total >= 0 && total < bestCost)
        {
            chosen = k;
            bestCost = total;
        }
    }
    if (chosen < 0)
        Fail(cg, loc, "interface '" + types.Name(iface) + "' has no method '" + name + "' that takes these arguments");
    var s = InterfaceMethod(cg, iface, chosen);

    Value self = ToRValue(cg, obj);
    string data = ir.ExtractValue("{ ptr, ptr }", self.V, "0");
    string table = ir.ExtractValue("{ ptr, ptr }", self.V, "1");
    string fn = ir.Load("ptr", ir.Gep("ptr", table, "i64 " + chosen.ToString()));

    var releaseSlots = List<TempRelease>.Create();
    var callArgs = StringBuilder.Create();
    callArgs.Append("ptr " + data);
    for (var i = 0; i < args.Length; i += 1)
    {
        SourceLoc aloc = args[i].Source.IsNull() ? loc : args[i].Source.Loc;
        int pt = s.ParamTypes[i];
        if (IsInterfaceType(cg, pt))
            callArgs.Append(", { ptr, ptr } " + InterfaceArgument(cg, args[i].V, pt, s.ParamRefs[i], releaseSlots, aloc));
        else if (s.ParamRefs[i] == 0)
        {
            Value cv = ConvertValue(cg, args[i].V, pt, aloc);
            HoldTemp(cg, cv);
            callArgs.Append(", " + AbiParam(cg, pt) + " " + cv.V);
        }
        else if (args[i].V.IsLValue)
            callArgs.Append(", ptr " + args[i].V.V);
        else
        {
            Value cv = ToRValue(cg, args[i].V);
            HoldTemp(cg, cv);
            string slot = ir.Alloca(LlvmType(cg, pt), "tmp");
            ir.Store(LlvmType(cg, pt), cv.V, slot);
            callArgs.Append(", ptr " + slot);
        }
    }
    string result = ir.Call(AbiReturn(cg, s.Ret), fn, callArgs.ToString());
    ReleaseInterfaceCopies(cg, releaseSlots);
    if (types.IsVoid(s.Ret))
        return Rvalue(types.Void, "", false);
    return Rvalue(s.Ret, result, NeedsArc(cg, s.Ret));
}

// 'shape is S v' for an interface parameter: true if it points to an S (its table is the one of S); v is a copy.
Value EmitInterfaceIs(Compiler cg, Value subj, int pattern, string bindName, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    if (!types.IsStruct(pattern))
        Fail(cg, loc, "an interface can only be matched against a struct type, not '" + types.Name(pattern) + "'");
    if (!StructImplements(cg, pattern, subj.Type))
        Fail(cg, loc, "'" + types.Name(pattern) + "' does not implement '" + types.Name(subj.Type) + "'");
    string table = InterfaceTable(cg, pattern, subj.Type);
    string flag = ir.ICmp("eq", "ptr", ir.ExtractValue("{ ptr, ptr }", subj.V, "1"), table);
    if (bindName.Length > 0)
    {
        string ty = LlvmType(cg, pattern);
        string slot = ir.Alloca(ty, bindName);
        ir.Allocas.Append("  store " + ty + " zeroinitializer, ptr " + slot + "\n");
        DeclareVar(cg, bindName, pattern, slot);
        var vars = cg.Fn[0].Vars;
        var last = vars.Get(vars.Count() - 1);
        last.ResetOnCleanup = true;
        vars.Set(vars.Count() - 1, last);
        // only when it matches: it may point to another struct
        string yes = ir.NewLabel("is.match");
        string done = ir.NewLabel("is.done");
        ir.CondBr(flag, yes, done);
        ir.SetBlock(yes);
        string value = ir.Load(ty, ir.ExtractValue("{ ptr, ptr }", subj.V, "0"));
        EmitRetain(cg, pattern, value);
        StoreSlot(cg, pattern, slot, value, true);
        ir.Br(done);
        ir.SetBlock(done);
    }
    return MakeBool(cg, flag);
}
