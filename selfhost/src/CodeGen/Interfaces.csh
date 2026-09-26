// Interface values (only in the self-hosted compiler): dynamic dispatch.
//
//     interface IShape { double Area(); }
//     struct Circle : IShape { double R; double Area() { return 3.14159 * R * R; } }
//
//     IShape shape = Circle { R = 2 };        // the struct is copied into a box
//     Console.WriteLine(shape.Area());        // calls Circle.Area through the method table
//     if (shape is Circle c) ...              // the struct again (a copy)
//
// An interface value is { ptr box, ptr table }. The box is a reference-counted block { i64 count, i64 unused, T value };
// copies of the interface value share it (like a boxed struct in C#), so a method that changes the struct changes it
// for every copy. The table is a constant per struct and interface: [drop, method 1, method 2, ...] in the order of
// the interface's methods; struct methods take 'this' as their first parameter, so the table holds them directly.
// 'drop' releases the struct in the box when the last reference goes away. A null interface value is { null, null }.

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
        sig.ParamTypes[i] = ResolveValueType(cg, m.Params[i].Type.Id, ie.File, ii.Env);
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
    entries.Append("ptr " + BoxDropHelper(cg, structType));
    for (var k = 0; k < count; k += 1)
    {
        int instance = FindImplementation(cg, structType, iface, k);
        if (instance < 0)
            Fail(cg, SourceLoc { }, "internal error: '" + types.Name(structType) + "' does not implement '" + InterfaceMethod(cg, iface, k).Name + "'");
        UseFunction(cg, instance);
        NoteCall(cg, instance); // may be called through the table
        entries.Append(", ptr " + cg.Instances.Get(instance).LlvmName);
    }
    cg.Ir.Globals.Append(name + " = internal constant [" + (count + 1).ToString() + " x ptr] [" + entries.ToString() + "]\n");
    return name;
}

// Releases the struct in a box whose last reference went away (the block itself is freed by the caller).
string BoxDropHelper(Compiler cg, int structType)
{
    string name = "@\"__box_drop." + cg.Types.Name(structType) + "\"";
    if (!cg.Ir.Declared.Add(name))
        return name;
    string text = "define internal void " + name + "(ptr %box) {\nentry:\n";
    if (NeedsArc(cg, structType))
    {
        string ty = LlvmType(cg, structType);
        text += "  %p = getelementptr i8, ptr %box, i64 16\n  %v = load " + ty + ", ptr %p\n" +
                "  call void " + ReleaseFunction(cg, structType) + "(" + ty + " %v)\n";
    }
    cg.Ir.AppendHelper(text + "  ret void\n}\n");
    return name;
}

string InterfaceRetainHelper(Compiler cg)
{
    string name = "@__cs_retain_iface";
    if (cg.Ir.Declared.Add(name))
        cg.Ir.AppendHelper("define internal void @__cs_retain_iface({ ptr, ptr } %v) {\nentry:\n" +
                           "  %box = extractvalue { ptr, ptr } %v, 0\n  call void @__cs_retain(ptr %box)\n  ret void\n}\n");
    return name;
}

string InterfaceReleaseHelper(Compiler cg)
{
    string name = "@__cs_release_iface";
    if (cg.Ir.Declared.Add(name))
        cg.Ir.AppendHelper("define internal void @__cs_release_iface({ ptr, ptr } %v) {\nentry:\n" +
                           "  %box = extractvalue { ptr, ptr } %v, 0\n" +
                           "  %isnull = icmp eq ptr %box, null\n  br i1 %isnull, label %done, label %dec\n" +
                           "dec:\n  %rc = load i64, ptr %box\n  %rc1 = sub i64 %rc, 1\n  store i64 %rc1, ptr %box\n" +
                           "  %last = icmp eq i64 %rc1, 0\n  br i1 %last, label %drop, label %done\n" +
                           "drop:\n  %table = extractvalue { ptr, ptr } %v, 1\n  %dropfn = load ptr, ptr %table\n" +
                           "  call void %dropfn(ptr %box)\n  call void @free(ptr %box)\n" +
                           (cg.St[0].ArcStats ? "  %fr = atomicrmw add ptr @__cs_frees, i64 1 monotonic\n" : "") +
                           "  br label %done\n" +
                           "done:\n  ret void\n}\n");
    return name;
}

// A struct value as an interface value: copied into a new box.
Value BoxAsInterface(Compiler cg, Value v, int iface, SourceLoc loc)
{
    var ir = cg.Ir;
    int st = v.Type;
    string table = InterfaceTable(cg, st, iface);
    string value = Consume(cg, ToRValue(cg, v));
    string box = ir.Call("ptr", "@__cs_alloc", "i64 " + SizeOfType(cg, st) + ", i64 0");
    ir.Store(LlvmType(cg, st), value, DataPtr(cg, box));
    string agg = ir.InsertValue("{ ptr, ptr }", "undef", "ptr", box, "0");
    return Rvalue(iface, ir.InsertValue("{ ptr, ptr }", agg, "ptr", table, "1"), true);
}

// iface.Method(args): the method from the table, called with the struct in the box as 'this'.
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
            int c = sig.ParamRefs[i] != 0 ? (args[i].V.Type == sig.ParamTypes[i] ? 0 : -1) : ConversionCost(cg, args[i].V, sig.ParamTypes[i]);
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
    HoldTemp(cg, self);
    string box = ir.ExtractValue("{ ptr, ptr }", self.V, "0");
    EmitPanicIf(cg, ir.ICmp("eq", "ptr", box, "null"), "call of a method of a null interface value");
    string table = ir.ExtractValue("{ ptr, ptr }", self.V, "1");
    string fn = ir.Load("ptr", ir.Gep("ptr", table, "i64 " + (chosen + 1).ToString()));

    var callArgs = StringBuilder.Create();
    callArgs.Append("ptr " + DataPtr(cg, box));
    for (var i = 0; i < args.Length; i += 1)
    {
        SourceLoc aloc = args[i].Source.IsNull() ? loc : args[i].Source.Loc;
        int pt = s.ParamTypes[i];
        if (s.ParamRefs[i] == 0)
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
    if (types.IsVoid(s.Ret))
        return Rvalue(types.Void, "", false);
    return Rvalue(s.Ret, result, NeedsArc(cg, s.Ret));
}

// 'x is S v' for an interface value: true if the box holds an S (its table is the one of S); v is a copy of it.
Value EmitInterfaceIs(Compiler cg, Value subj, int pattern, string bindName, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    if (!types.IsStruct(pattern))
        Fail(cg, loc, "an interface value can only be matched against a struct type, not '" + types.Name(pattern) + "'");
    if (!StructImplements(cg, pattern, subj.Type))
        Fail(cg, loc, "'" + types.Name(pattern) + "' does not implement '" + types.Name(subj.Type) + "'");
    HoldTemp(cg, subj);
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
        // only when it matches: the box may hold another struct
        string yes = ir.NewLabel("is.match");
        string done = ir.NewLabel("is.done");
        ir.CondBr(flag, yes, done);
        ir.SetBlock(yes);
        string value = ir.Load(ty, DataPtr(cg, ir.ExtractValue("{ ptr, ptr }", subj.V, "0")));
        EmitRetain(cg, pattern, value);
        StoreSlot(cg, pattern, slot, value, true);
        ir.Br(done);
        ir.SetBlock(done);
    }
    return MakeBool(cg, flag);
}
