// Sum types (only in the self-hosted compiler): one of several member types, stored inline with a tag.
//
//     union Shape : IShape { Circle, Rect }
//
//     Shape s = Circle { R = 1.0 };                  // a member converts to the union (no allocation)
//     if (s is Rect r) ...                           // is / switch (case Circle c:) get the member back (a copy)
//     double a = s.Area();                           // IShape's methods are dispatched on the tag
//     Describe(s);                                   // passes as 'const ref IShape' (points into the union)
//     var shapes = List<Shape>.Create();             // different shapes in one list, stored inline
//
// Layout: { i32 tag, [payload] }; the payload has the size and alignment of the largest member. Tag 0 is the default
// value (empty); member k has tag k + 1. The interfaces a union lists must be implemented by every member; a method of
// such an interface is called through the member's method table (Interfaces.csh), picked by the tag, with 'this'
// pointing into the union - so a method that changes the member changes it in place. Calling a method of an empty
// union panics.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

struct UnionInfo
{
    int Entry;          // index in Compiler.Unions
    string Name;
    int Type;
    int[] Members;
    int[] Interfaces;
    string IrName;
    int64 Size;
    int64 Align;
    bool InProgress;
}

UnionInfo GetUnionInfo(Compiler cg, int t)
{
    return cg.UnionInfos.Get(cg.Types.Decl(t));
}

bool IsUnionType(Compiler cg, int t)
{
    return cg.Types.Kind(t) == TypeKind.Union;
}

// The union type of a declaration (created with its layout the first time it is used).
int GetUnionType(Compiler cg, int index, SourceLoc loc)
{
    var types = cg.Types;
    var ue = cg.Unions.Get(index);
    if (ue.Type != 0)
    {
        if (GetUnionInfo(cg, ue.Type).InProgress)
            Fail(cg, ue.Decl.Loc, "union '" + ue.Decl.Name + "' contains itself");
        return ue.Type;
    }
    var decl = ue.Decl;
    string key = Qualified(cg, ue.File, decl.Name);
    int t = types.Add(TypeKind.Union, key, 0, false);
    var info = UnionInfo { Entry = index, Name = key, Type = t, IrName = "%\"" + key + "\"", InProgress = true, Align = 4 };
    info.Members = new int[0];
    info.Interfaces = new int[0];
    cg.UnionInfos.Add(info);
    int infoIndex = cg.UnionInfos.Count() - 1;
    var ti = types.Info(t);
    ti.Decl = infoIndex;
    types.SetInfo(t, ti);
    ue.Type = t;
    cg.Unions.Set(index, ue);

    // the members and the size of the payload
    var members = new int[decl.Members.Length];
    int64 size = 0;
    int64 align = 1;
    for (var i = 0; i < members.Length; i += 1)
    {
        int m = ResolveValueType(cg, decl.Members[i].Id, ue.File, NoEnv());
        var mloc = cg.Tree.GetType(decl.Members[i]).Loc;
        var kind = types.Kind(m);
        if (kind == TypeKind.Void || kind == TypeKind.Null)
            Fail(cg, mloc, "'" + types.Name(m) + "' cannot be a member of a union");
        for (var k = 0; k < i; k += 1)
        {
            if (members[k] == m)
                Fail(cg, mloc, "'" + types.Name(m) + "' is a member of union '" + decl.Name + "' twice");
        }
        if (IsUnionType(cg, m) && GetUnionInfo(cg, m).InProgress)
            Fail(cg, mloc, "union '" + decl.Name + "' contains itself");
        members[i] = m;
        var l = TypeLayout(cg, m);
        if (l.Size > size)
            size = l.Size;
        if (l.Align > align)
            align = l.Align;
    }
    int64 unit = align;
    int64 count = (size + unit - 1) / unit;
    cg.Ir.Globals.Append(info.IrName + " = type { i32, [" + count.ToString() + " x i" + (unit * 8).ToString() + "] }\n");
    int64 total = (align > 4 ? align : 4) + count * unit;
    int64 outer = align > 4 ? align : 4;
    info = cg.UnionInfos.Get(infoIndex);
    info.Members = members;
    info.Size = (total + outer - 1) / outer * outer;
    info.Align = outer;

    // the interfaces: every member has to implement them
    var interfaces = new int[decl.Interfaces.Length];
    for (var i = 0; i < interfaces.Length; i += 1)
    {
        int iface = ResolveType(cg, decl.Interfaces[i].Id, ue.File, NoEnv());
        var iloc = cg.Tree.GetType(decl.Interfaces[i]).Loc;
        if (!IsInterfaceType(cg, iface))
            Fail(cg, iloc, "'" + types.Name(iface) + "' is not an interface");
        foreach (var m in members)
        {
            if (!types.IsStruct(m) || !StructImplements(cg, m, iface))
                Fail(cg, iloc, "'" + types.Name(m) + "' does not implement '" + types.Name(iface) + "', so union '" + decl.Name + "' cannot list it");
        }
        interfaces[i] = iface;
    }
    info.Interfaces = interfaces;
    info.InProgress = false;
    cg.UnionInfos.Set(infoIndex, info);
    return t;
}

// The position of the type among the members of the union (its tag is that + 1), -1 if it is not a member.
int UnionMemberIndex(Compiler cg, int union, int t)
{
    var members = GetUnionInfo(cg, union).Members;
    for (var i = 0; i < members.Length; i += 1)
    {
        if (members[i] == t)
            return i;
    }
    return -1;
}

bool UnionImplements(Compiler cg, int union, int iface)
{
    foreach (var i in GetUnionInfo(cg, union).Interfaces)
    {
        if (i == iface)
            return true;
    }
    return false;
}

// Memory that holds the union value: the variable itself, or a temporary copy.
string UnionSlot(Compiler cg, Value v)
{
    if (v.IsLValue)
        return v.V;
    HoldTemp(cg, v);
    string ty = LlvmType(cg, v.Type);
    string slot = cg.Ir.Alloca(ty, "union");
    cg.Ir.Store(ty, v.V, slot);
    return slot;
}

string UnionTag(Compiler cg, int union, string slot)
{
    return cg.Ir.Load("i32", cg.Ir.Gep(GetUnionInfo(cg, union).IrName, slot, "i32 0, i32 0"));
}

string UnionPayload(Compiler cg, int union, string slot)
{
    return cg.Ir.Gep(GetUnionInfo(cg, union).IrName, slot, "i32 0, i32 1");
}

// A member value as a union value (owned, like the member it was made from).
Value UnionFromMember(Compiler cg, Value v, int union, int index)
{
    var ir = cg.Ir;
    string ty = LlvmType(cg, union);
    string slot = ir.Alloca(ty, "union.new");
    ir.Store(ty, "zeroinitializer", slot);
    ir.Store("i32", (index + 1).ToString(), ir.Gep(GetUnionInfo(cg, union).IrName, slot, "i32 0, i32 0"));
    int member = GetUnionInfo(cg, union).Members[index];
    ir.Store(LlvmType(cg, member), Consume(cg, ToRValue(cg, v)), UnionPayload(cg, union, slot));
    return Rvalue(union, ir.Load(ty, slot), NeedsArc(cg, union));
}

// 'u is M m' / 'case M m:': true if the union holds an M; m is a copy of it.
Value EmitUnionIs(Compiler cg, Value subj, int pattern, string bindName, SourceLoc loc)
{
    var types = cg.Types;
    var ir = cg.Ir;
    int index = UnionMemberIndex(cg, subj.Type, pattern);
    if (index < 0)
        Fail(cg, loc, "'" + types.Name(pattern) + "' is not a member of union '" + types.Name(subj.Type) + "'");
    string slot = UnionSlot(cg, subj);
    string flag = ir.ICmp("eq", "i32", UnionTag(cg, subj.Type, slot), (index + 1).ToString());
    if (bindName.Length > 0)
        BindUnionMember(cg, subj.Type, slot, pattern, flag, bindName);
    return MakeBool(cg, flag);
}

// Declares 'name' and, if 'flag' is true, copies the member into it.
void BindUnionMember(Compiler cg, int union, string slot, int member, string flag, string name)
{
    var ir = cg.Ir;
    string ty = LlvmType(cg, member);
    string target = ir.Alloca(ty, name);
    ir.Allocas.Append("  store " + ty + " " + ZeroValue(cg, member) + ", ptr " + target + "\n");
    DeclareVar(cg, name, member, target);
    var vars = cg.Fn[0].Vars;
    var last = vars.Get(vars.Count() - 1);
    last.ResetOnCleanup = true;
    vars.Set(vars.Count() - 1, last);
    string yes = ir.NewLabel("union.match");
    string done = ir.NewLabel("union.done");
    ir.CondBr(flag, yes, done);
    ir.SetBlock(yes);
    string value = ir.Load(ty, UnionPayload(cg, union, slot));
    EmitRetain(cg, member, value);
    StoreSlot(cg, member, target, value, true);
    ir.Br(done);
    ir.SetBlock(done);
}

// The method tables of the members for the interface, indexed by the tag (tag 0: none).
string UnionTables(Compiler cg, int union, int iface)
{
    var types = cg.Types;
    string name = "@\"utable." + types.Name(union) + "." + types.Name(iface) + "\"";
    if (!cg.Ir.Declared.Add(name))
        return name;
    var members = GetUnionInfo(cg, union).Members;
    var entries = StringBuilder.Create();
    entries.Append("ptr null");
    foreach (var m in members)
        entries.Append(", ptr " + InterfaceTable(cg, m, iface));
    cg.Ir.Globals.Append(name + " = internal constant [" + (members.Length + 1).ToString() + " x ptr] [" + entries.ToString() + "]\n");
    return name;
}

// The { data, table } of the member in the union at 'slot', as the interface.
string UnionAsInterface(Compiler cg, int union, string slot, int iface)
{
    var ir = cg.Ir;
    string tag = UnionTag(cg, union, slot);
    EmitPanicIf(cg, ir.ICmp("eq", "i32", tag, "0"), "the union '" + cg.Types.Name(union) + "' holds no value");
    string wide = ir.Cast("zext", "i32", tag, "i64");
    string table = ir.Load("ptr", ir.Gep("ptr", UnionTables(cg, union, iface), "i64 " + wide));
    string agg = ir.InsertValue("{ ptr, ptr }", "undef", "ptr", UnionPayload(cg, union, slot), "0");
    return ir.InsertValue("{ ptr, ptr }", agg, "ptr", table, "1");
}

// u.Method(args): a method of one of the union's interfaces, called on the member it holds.
Value EmitUnionCall(Compiler cg, Value obj, string name, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    int union = obj.Type;
    foreach (var iface in GetUnionInfo(cg, union).Interfaces)
    {
        int count = InterfaceMethodCount(cg, iface);
        for (var k = 0; k < count; k += 1)
        {
            if (InterfaceMethod(cg, iface, k).Name != name)
                continue;
            // a variable is changed in place by the method; a temporary value is called on a copy
            string slot = obj.IsLValue && !obj.IsConst ? obj.V : UnionSlot(cg, ToRValue(cg, obj));
            return EmitInterfaceCall(cg, Rvalue(iface, UnionAsInterface(cg, union, slot, iface), false), name, args, loc);
        }
    }
    Fail(cg, loc, "union '" + types.Name(union) + "' has no method '" + name + "' (it can call the methods of the interfaces it lists)");
    return obj;
}

// Retain/release of a union value: the one of the member it holds.
string UnionHelper(Compiler cg, int union, bool isRetain)
{
    var types = cg.Types;
    string name = "@\"" + (isRetain ? "__retain." : "__release.") + types.Name(union) + "\"";
    if (!cg.Ir.Declared.Add(name))
        return name;
    var info = GetUnionInfo(cg, union);
    string ty = info.IrName;
    var sb = StringBuilder.Create();
    sb.Append("define internal void " + name + "(" + ty + " %v) {\nentry:\n");
    sb.Append("  %slot = alloca " + ty + "\n  store " + ty + " %v, ptr %slot\n");
    sb.Append("  %tagp = getelementptr " + ty + ", ptr %slot, i32 0, i32 0\n  %tag = load i32, ptr %tagp\n");
    sb.Append("  %payload = getelementptr " + ty + ", ptr %slot, i32 0, i32 1\n");
    sb.Append("  switch i32 %tag, label %done [");
    for (var i = 0; i < info.Members.Length; i += 1)
    {
        if (NeedsArc(cg, info.Members[i]))
            sb.Append(" i32 " + (i + 1).ToString() + ", label %m" + i.ToString());
    }
    sb.Append(" ]\n");
    for (var i = 0; i < info.Members.Length; i += 1)
    {
        int m = info.Members[i];
        if (!NeedsArc(cg, m))
            continue;
        string mty = LlvmType(cg, m);
        string fn = isRetain ? RetainFunction(cg, m) : ReleaseFunction(cg, m);
        sb.Append("m" + i.ToString() + ":\n  %v" + i.ToString() + " = load " + mty + ", ptr %payload\n");
        sb.Append("  call void " + fn + "(" + mty + " %v" + i.ToString() + ")\n  br label %done\n");
    }
    sb.Append("done:\n  ret void\n}\n");
    cg.Ir.AppendHelper(sb.ToString());
    return name;
}
